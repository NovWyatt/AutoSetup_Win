<#
  AutoSetup_Win - chép AutoSetup lên USB Ventoy và cập nhật ventoy.json.

  Trên USB sau khi chạy:
    \AutoSetup\unattend\*.xml   6 file unattend (sinh lại bằng TaoUnattend.ps1, trừ khi -KhongSinhLai)
    \AutoSetup\sau-cai\         bước sau cài (SauCai.ps1, CHAY_LAI.bat)
    \AutoSetup\cau-hinh\        CauHinh.json (đã gộp CauHinh.local.json), UngDung.json (hoặc UngDung.local.json)
    \AutoSetup\office\          bạn tự thêm: Office Deployment Tool (setup.exe + cau-hinh.xml, có thể kèm Office\Data)
    \AutoSetup\drivers\         bạn tự thêm: driver dạng .inf (vd thư mục xuất bằng pnputil /export-driver)
    \AutoSetup\ket_qua\         báo cáo của các máy đã cài
    \ventoy\ventoy.json         thêm mục auto_install cho các ISO Windows trên USB; giữ nguyên các phần khác,
                                sao lưu bản cũ thành ventoy.json.bak-<giờ>
  Chép ISO Windows lên USB trước (tên file khớp ventoy.locTenIso, vd Win11_24H2_x64.iso), rồi chạy lại khi thêm ISO.

  Tham số:
    -O <ổ hoặc thư mục>   USB đích (mặc định: tự tìm phân vùng có nhãn "Ventoy")
    -ChayThu              chỉ in việc sẽ làm, không ghi gì
    -KhongSinhLai         dùng file đã có trong out\unattend
    -DiskId, -MatKhauFile, -KhongMatKhau: chuyển cho TaoUnattend.ps1
  Mã thoát: 0 xong, 1 lỗi, 2 không thấy USB.
#>
[CmdletBinding()]
param(
    [string]$O = '',
    [switch]$ChayThu,
    [switch]$KhongSinhLai,
    [string]$DiskId = '',
    [string]$MatKhauFile = '',
    [switch]$KhongMatKhau,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\CauHinh.ps1')
. (Join-Path $repo 'sau-cai\lib\Chung.ps1')
$script:OutDir = if ($env:AUTOSETUP_OUT) { $env:AUTOSETUP_OUT } else { Join-Path $repo 'out\unattend' }   # bài thử đặt AUTOSETUP_OUT
$script:UsbBase = '/AutoSetup/unattend/'

function Wait-Close {
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host '  Bấm Enter để đóng cửa sổ')
}

function Find-VentoyRoot {
    # Gốc phân vùng dữ liệu của USB Ventoy (nhãn "Ventoy"). Trả chuỗi 'E:\' hoặc $null; nhiều USB thì báo lỗi.
    $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'Ventoy' -and $_.DriveLetter })
    if ($vols.Count -gt 1) { throw ('Có {0} USB Ventoy ({1}). Chọn một bằng -O <ổ>.' -f $vols.Count, (($vols | ForEach-Object { "$($_.DriveLetter):" }) -join ', ')) }
    if (-not $vols.Count) { return $null }
    return ('{0}:\' -f $vols[0].DriveLetter)
}

function Get-VentoyPath {
    # Đường dẫn kiểu Ventoy (/thu-muc/file.iso) của một file trên USB.
    param([string]$Root, [string]$FullName)
    $rel = $FullName.Substring($Root.TrimEnd('\').Length).TrimStart('\')
    return '/' + $rel.Replace('\', '/')
}

function Find-WindowsIsos {
    param([string]$Root, [string]$Pattern)
    $skip = @((Join-Path $Root 'AutoSetup'), (Join-Path $Root 'ventoy'))
    $isos = @(Get-ChildItem -LiteralPath $Root -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $f = $_.FullName; -not @($skip | Where-Object { $f.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count } |
        Where-Object { $_.Name -match $Pattern } | Sort-Object FullName)
    return , $isos
}

function Update-VentoyJson {
    # Gộp mục auto_install của AutoSetup vào ventoy.json. Trả @{ Json; Changed; Old }.
    param($Existing, [string[]]$IsoPaths, [string[]]$Templates, [int]$Timeout, [int]$AutoSel)
    $r = [ordered]@{}
    if ($Existing) { foreach ($p in $Existing.PSObject.Properties) { $r[$p.Name] = $p.Value } }
    $keep = @()
    foreach ($e in @($r['auto_install'])) {
        if ($null -eq $e) { continue }
        $img = [string]$e.image
        $tpl = @($e.template) -join ' '
        if ($img -and $img -in $IsoPaths) { continue }                  # ISO của mình: thay bằng mục mới
        if ($tpl -like "*$($script:UsbBase)*" -and -not $e.parent) { continue }   # mục AutoSetup cũ (ISO đã xoá)
        $keep += $e
    }
    foreach ($iso in $IsoPaths) {
        $keep += [pscustomobject][ordered]@{ image = $iso; template = $Templates; timeout = $Timeout; autosel = $AutoSel }
    }
    $r['auto_install'] = $keep
    return [pscustomobject]$r
}

try {
    Write-Head 'CHÉP AUTOSETUP LÊN USB VENTOY'
    $root = if ($O) { $O } else { Find-VentoyRoot }
    if (-not $root) { Write-Bad 'Không thấy USB Ventoy (phân vùng nhãn "Ventoy"). Cắm USB đã cài Ventoy, hoặc chỉ định -O <ổ>.'; Wait-Close; exit 2 }
    if ($root -match '^[A-Za-z]:$') { $root += '\' }
    if (-not (Test-Path -LiteralPath $root)) { throw "Không thấy $root" }
    $root = (Resolve-Path -LiteralPath $root).Path
    if (-not $root.EndsWith('\')) { $root += '\' }
    if ($root.TrimEnd('\') -ieq $env:SystemDrive) { throw 'Không chép vào ổ Windows.' }
    Write-Info "USB đích: $root"

    $cfgPath = Join-Path $repo 'cau-hinh\CauHinh.json'
    $cfg = Get-AutoSetupConfig $cfgPath
    $errs = Test-AutoSetupConfig $cfg
    if ($errs.Count) { Write-Bad 'Cấu hình có lỗi:'; foreach ($e in $errs) { Write-Sub $e }; Wait-Close; exit 1 }

    if (-not $KhongSinhLai) {
        $tuArgs = @{ Ra = $script:OutDir; KhongDung = $true }
        if ($DiskId -ne '') { $tuArgs.DiskId = $DiskId }
        if ($MatKhauFile) { $tuArgs.MatKhauFile = $MatKhauFile }
        if ($KhongMatKhau) { $tuArgs.KhongMatKhau = $true }
        & (Join-Path $PSScriptRoot 'TaoUnattend.ps1') @tuArgs
        if ($LASTEXITCODE -ne 0) { throw 'Sinh file unattend lỗi (xem phía trên).' }
    }
    $list = Read-JsonFile (Join-Path $script:OutDir 'DanhSach.json')
    $templates = @($list.tep | ForEach-Object { $script:UsbBase + $_.tep })
    foreach ($t in $list.tep) { if (-not (Test-Path -LiteralPath (Join-Path $script:OutDir $t.tep))) { throw "Thiếu $($t.tep) trong $($script:OutDir). Chạy lại không có -KhongSinhLai." } }

    $as = Join-Path $root 'AutoSetup'
    $appList = Join-Path $repo 'cau-hinh\UngDung.local.json'
    if (-not (Test-Path -LiteralPath $appList)) { $appList = Join-Path $repo 'cau-hinh\UngDung.json' }
    $pattern = [string](Get-ConfigValue $cfg 'ventoy.locTenIso' '(?i)win')
    $isos = Find-WindowsIsos $root $pattern
    $isoPaths = @($isos | ForEach-Object { Get-VentoyPath $root $_.FullName })

    Write-Head 'Việc sẽ làm'
    Write-Plan "Chép 6 file unattend vào $as\unattend"
    Write-Plan "Chép bước sau cài vào $as\sau-cai"
    Write-Plan "Ghi cấu hình vào $as\cau-hinh (UngDung từ $(Split-Path -Leaf $appList))"
    Write-Plan "Tạo $as\office, $as\drivers, $as\ket_qua nếu chưa có"
    if ($isoPaths.Count) { foreach ($p in $isoPaths) { Write-Plan "ventoy.json: menu cài tự động cho $p" } }
    else { Write-Warn "Chưa có ISO Windows nào trên USB khớp '$pattern'. Chép ISO lên USB rồi chạy lại để thêm menu cài tự động." }
    if ($ChayThu) { Write-Info 'Chạy thử: không ghi gì.'; Wait-Close; exit 0 }

    foreach ($sub in 'unattend', 'sau-cai', 'cau-hinh', 'office', 'drivers', 'ket_qua') { New-Item -ItemType Directory -Path (Join-Path $as $sub) -Force | Out-Null }
    Get-ChildItem -LiteralPath (Join-Path $as 'unattend') -Filter '*.xml' -File | Remove-Item -Force
    foreach ($t in $list.tep) { Copy-Item -LiteralPath (Join-Path $script:OutDir $t.tep) -Destination (Join-Path $as 'unattend') -Force }
    Remove-Item -LiteralPath (Join-Path $as 'sau-cai') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'sau-cai') -Destination (Join-Path $as 'sau-cai') -Recurse -Force
    Write-JsonFile (Join-Path $as 'cau-hinh\CauHinh.json') $cfg
    Copy-Item -LiteralPath $appList -Destination (Join-Path $as 'cau-hinh\UngDung.json') -Force
    $notes = @{
        'office\DOC-TRUOC.txt'  = "Đặt Office Deployment Tool vào đây để bước sau cài tự cài Office:`r`n  setup.exe      (tải ODT: https://www.microsoft.com/download/details.aspx?id=49117)`r`n  cau-hinh.xml   (tạo tại https://config.office.com, có thể sửa từ docs\office-mau.xml trong repo)`r`n  Office\Data    (không bắt buộc: chạy 'setup.exe /download cau-hinh.xml' để cài không cần mạng)`r`nKhông có setup.exe thì bước Office được bỏ qua.`r`n"
        'drivers\DOC-TRUOC.txt' = "Đặt driver dạng .inf vào đây (mọi thư mục con), bước sau cài nạp bằng pnputil /add-driver /subdirs /install.`r`nVd: xuất driver máy cũ bằng 'pnputil /export-driver * <thư mục>'. Driver còn thiếu được tải tiếp từ Windows Update.`r`n"
    }
    foreach ($k in $notes.Keys) { [IO.File]::WriteAllText((Join-Path $as $k), $notes[$k], (New-Object Text.UTF8Encoding $true)) }
    Write-Ok "Đã chép AutoSetup vào $as"

    $vdir = Join-Path $root 'ventoy'
    $vjson = Join-Path $vdir 'ventoy.json'
    if ($isoPaths.Count) {
        $old = $null; $oldText = ''
        if (Test-Path -LiteralPath $vjson) { $oldText = [IO.File]::ReadAllText($vjson, [Text.Encoding]::UTF8); $old = Read-JsonFile $vjson }
        $new = Update-VentoyJson -Existing $old -IsoPaths $isoPaths -Templates $templates -Timeout ([int](Get-ConfigValue $cfg 'ventoy.choChonGiay' 15)) -AutoSel ([int](Get-ConfigValue $cfg 'ventoy.macDinh' 1))
        $newText = (ConvertTo-JsonText $new) + "`n"
        if ($newText -ne $oldText) {
            New-Item -ItemType Directory -Path $vdir -Force | Out-Null
            if ($oldText) {
                $bak = Join-Path $vdir ('ventoy.json.bak-{0:yyyyMMdd_HHmmss}' -f (Get-Date))
                Copy-Item -LiteralPath $vjson -Destination $bak
                Write-Info "Sao lưu ventoy.json cũ: $bak"
            }
            Write-JsonFile $vjson $new
            Write-Ok "Đã cập nhật $vjson ($($isoPaths.Count) ISO)"
        } else { Write-Ok 'ventoy.json đã đúng, không đổi.' }
    }
    Write-Line ''
    Write-Info 'Khởi động máy cần cài bằng USB, chọn ISO Windows rồi chọn một file trong menu AutoSetup.'
    Write-Info "Mặc định sau $([int](Get-ConfigValue $cfg 'ventoy.choChonGiay' 15)) giây: mục $([int](Get-ConfigValue $cfg 'ventoy.macDinh' 1)) (1 = tự chọn ổ, không xoá gì)."
    Wait-Close
    exit 0
} catch {
    Write-Bad $_.Exception.Message
    Wait-Close
    exit 1
}
