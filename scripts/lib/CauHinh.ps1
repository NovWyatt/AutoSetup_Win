<#
  Đọc và kiểm tra cấu hình (cau-hinh\CauHinh.json, ghi đè bằng cau-hinh\CauHinh.local.json nếu có).
  Dùng chung cho TaoUnattend.ps1 và TaoUSB.ps1.
#>

. (Join-Path $PSScriptRoot '..\..\sau-cai\lib\Json.ps1')

# Key cài đặt chung của Microsoft cho từng phiên bản: chỉ để Windows Setup chọn đúng phiên bản, KHÔNG kích hoạt Windows.
# Nguồn: bảng WindowsEdition.json của schneegans/unattend-generator (MIT).
$script:GenericKeys = [ordered]@{
    'home'             = @{ Ten = 'Home'; Key = 'YTMG3-N6DKC-DKB77-7M9GH-8HVX7' }
    'home_n'           = @{ Ten = 'Home N'; Key = '4CPRK-NM3K3-X6XXQ-RXX86-WXCHW' }
    'home_single'      = @{ Ten = 'Home Single Language'; Key = 'BT79Q-G7N6G-PGBYW-4YWX6-6F4BT' }
    'education'        = @{ Ten = 'Education'; Key = 'YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY' }
    'education_n'      = @{ Ten = 'Education N'; Key = '84NGF-MHBT6-FXBX8-QWJK7-DRR8H' }
    'pro'              = @{ Ten = 'Pro'; Key = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' }
    'pro_n'            = @{ Ten = 'Pro N'; Key = '2B87N-8KFHP-DKV6R-Y2C8J-PKCKT' }
    'pro_education'    = @{ Ten = 'Pro Education'; Key = '8PTT6-RNW4C-6V7J2-C2D3X-MHBPB' }
    'pro_workstations' = @{ Ten = 'Pro for Workstations'; Key = 'DXG7C-N36C4-C4HTG-X4T3X-2YV77' }
    'enterprise'       = @{ Ten = 'Enterprise'; Key = 'XGVPP-NMH47-7TTHJ-W3FW7-8HV2C' }
}

$script:SearchModes = @{ 'an' = 0; 'icon' = 1; 'o' = 2; 'nhan' = 3 }

function Merge-ConfigObject {
    # Ghi đè $Override lên $Base theo từng khoá (đệ quy với đối tượng; mảng và giá trị đơn thì thay cả).
    param($Base, $Override)
    if ($null -eq $Override) { return $Base }
    if (-not ($Base -is [Management.Automation.PSCustomObject]) -or -not ($Override -is [Management.Automation.PSCustomObject])) { return $Override }
    $r = [ordered]@{}
    foreach ($p in $Base.PSObject.Properties) { $r[$p.Name] = $p.Value }
    foreach ($p in $Override.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }   # khoá bắt đầu bằng _ là ghi chú
        if ($r.Contains($p.Name)) { $r[$p.Name] = Merge-ConfigObject $r[$p.Name] $p.Value } else { $r[$p.Name] = $p.Value }
    }
    return [pscustomobject]$r
}

function Get-AutoSetupConfig {
    # Cấu hình hiệu lực: CauHinh.json, ghi đè bằng CauHinh.local.json cùng thư mục (không commit) nếu có.
    param([Parameter(Mandatory)][string]$Path)
    $cfg = Read-JsonFile $Path
    $local = Join-Path (Split-Path -Parent $Path) (([IO.Path]::GetFileNameWithoutExtension($Path)) + '.local.json')
    if (Test-Path -LiteralPath $local) { $cfg = Merge-ConfigObject $cfg (Read-JsonFile $local) }
    return $cfg
}

function Get-ConfigValue {
    # Lấy giá trị theo đường dẫn 'a.b.c'; không có thì trả $Default.
    param($Config, [string]$Path, $Default = $null)
    $cur = $Config
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $Default }
        $prop = $cur.PSObject.Properties[$part]
        if (-not $prop) { return $Default }
        $cur = $prop.Value
    }
    if ($null -eq $cur) { return $Default }
    return $cur
}

function Test-ComputerName {
    # Tên máy hợp lệ: 1-15 ký tự chữ, số, dấu gạch ngang; không toàn số; không bắt đầu, kết thúc bằng '-'.
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9-]{1,15}$' -and $Name -notmatch '^\d+$' -and $Name -notmatch '^-|-$')
}

function Test-AccountName {
    # Tên tài khoản local: 1-20 ký tự không dấu (Setup đổi chữ có dấu trong file unattend thành '?'), không có ký tự
    # cấm, không trùng tên có sẵn của Windows.
    param([string]$Name)
    if (-not $Name -or $Name.Length -gt 20 -or $Name -notmatch '^[\x20-\x7E]+$') { return $false }
    if ($Name -match '["/\\\[\]:;|=,+*?<>@]' -or $Name.Trim() -ne $Name -or $Name.EndsWith('.')) { return $false }
    return ($Name -notin 'Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'SYSTEM', 'defaultuser0')
}

function Test-AutoSetupConfig {
    # Trả danh sách lỗi (chuỗi tiếng Việt); rỗng là cấu hình dùng được.
    param($Config)
    $err = New-Object System.Collections.Generic.List[string]
    $v = { param($p, $d = $null) Get-ConfigValue $Config $p $d }

    foreach ($k in 'giaoDien', 'dinhDang', 'heThong') {
        if ((& $v "ngonNgu.$k" '') -notmatch '^[a-z]{2,3}-[A-Za-z]{2,4}(-[A-Za-z]+)?$') { $err.Add("ngonNgu.$k phải là mã ngôn ngữ dạng en-US, vi-VN.") }
    }
    if ((& $v 'ngonNgu.banPhim' '') -notmatch '^[0-9a-fA-F]{4}:([0-9a-fA-F]{8}|\{[0-9a-fA-F-]{36}\}\{[0-9a-fA-F-]{36}\})(;.+)?$') {
        $err.Add('ngonNgu.banPhim phải dạng 0409:00000409 (mã ngôn ngữ:mã bàn phím).')
    }
    if (-not (& $v 'ngonNgu.muiGio' '')) { $err.Add('ngonNgu.muiGio đang trống (vd SE Asia Standard Time).') }
    $geo = & $v 'ngonNgu.quocGia' $null
    if (-not ($geo -is [int] -or $geo -is [long]) -or $geo -le 0) { $err.Add('ngonNgu.quocGia phải là số GeoId (Việt Nam là 251).') }

    $bq = & $v 'banQuyen.cheDo' ''
    if ($bq -notin 'bios', 'hoi', 'key-chung') { $err.Add('banQuyen.cheDo phải là bios, hoi hoặc key-chung.') }
    if ($bq -eq 'key-chung' -and -not $script:GenericKeys.Contains([string](& $v 'banQuyen.phienBanWindows' ''))) {
        $err.Add('banQuyen.phienBanWindows phải là một trong: ' + (@($script:GenericKeys.Keys) -join ', ') + '.')
    }

    $tk = & $v 'taiKhoan.cheDo' ''
    if ($tk -notin 'hoi', 'tu-dong') { $err.Add('taiKhoan.cheDo phải là hoi hoặc tu-dong.') }
    if ($tk -eq 'tu-dong' -and -not (Test-AccountName ([string](& $v 'taiKhoan.ten' '')))) {
        $err.Add('taiKhoan.ten không hợp lệ (1-20 ký tự không dấu, không có " / \ [ ] : ; | = , + * ? < > @, không dùng tên có sẵn như Administrator).')
    }

    $name = [string](& $v 'tenMay' '*')
    if ($name -notin '*', 'hoi' -and -not (Test-ComputerName $name)) { $err.Add('tenMay phải là *, hoi hoặc tên 1-15 ký tự chữ, số, dấu gạch ngang.') }

    $sys = & $v 'oDia.heThongMB' 0; $c = & $v 'oDia.dungLuongC_GB' 0; $min = & $v 'oDia.toiThieuGB' 0
    if ($sys -lt 100 -or $sys -gt 2000) { $err.Add('oDia.heThongMB phải từ 100 đến 2000.') }
    if ($c -lt 40 -or $c -gt 10000) { $err.Add('oDia.dungLuongC_GB phải từ 40 đến 10000.') }
    if ($min -lt 30 -or $min -gt 10000) { $err.Add('oDia.toiThieuGB phải từ 30 đến 10000.') }

    if (-not $script:SearchModes.ContainsKey([string](& $v 'tinhChinh.timKiem' 'icon'))) { $err.Add('tinhChinh.timKiem phải là an, icon, o hoặc nhan.') }
    foreach ($list in 'goBo.ungDung', 'goBo.capability', 'goBo.tinhNang') {
        foreach ($item in @(& $v $list @())) {
            if ([string]$item -notmatch '^[A-Za-z0-9._~-]+$') { $err.Add("$list có mục không hợp lệ: '$item'.") }
        }
    }
    $wait = & $v 'sauCai.choMangPhut' 10
    if ($wait -lt 0 -or $wait -gt 120) { $err.Add('sauCai.choMangPhut phải từ 0 đến 120.') }
    $limit = & $v 'sauCai.choCaiPhut' 30
    if ($limit -lt 5 -or $limit -gt 600) { $err.Add('sauCai.choCaiPhut phải từ 5 đến 600.') }
    $dir = [string](& $v 'sauCai.thuMucCai' '')
    if ($dir -and $dir -notmatch '^[A-Za-z]:\\') { $err.Add('sauCai.thuMucCai phải là đường dẫn đầy đủ (vd D:\Program Files) hoặc để trống.') }
    $sel = & $v 'ventoy.macDinh' 1
    if ($sel -lt 0 -or $sel -gt 6) { $err.Add('ventoy.macDinh phải từ 0 đến 6.') }
    return , $err.ToArray()
}
