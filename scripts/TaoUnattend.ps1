<#
  AutoSetup_Win - sinh các file unattend (autounattend.xml) cho USB Ventoy từ cau-hinh\CauHinh.json.

  Ra thư mục out\unattend (mặc định):
    1_Chon-o-bang-tay.xml                     tự chọn ổ, phân vùng trong Windows Setup; có bước sau cài
    2_Chon-o-bang-tay_Chi-Windows.xml         như trên, không chạy bước sau cài
    3_XOA-SACH-o_1-phan-vung.xml              XOÁ SẠCH ổ, tạo một phân vùng C; có bước sau cài
    4_XOA-SACH-o_1-phan-vung_Chi-Windows.xml
    5_XOA-SACH-o_chia-C-D.xml                 XOÁ SẠCH ổ, chia C (oDia.dungLuongC_GB) và D (phần còn lại)
    6_XOA-SACH-o_chia-C-D_Chi-Windows.xml
    DanhSach.json                             tên, mô tả từng file (TaoUSB.ps1 dùng)
  Bản xoá ổ có bước kiểm tra trong WinPE (unattend\KiemTraO.vbs): chỉ xoá khi máy khởi động UEFI và có đúng MỘT
  ổ trong (không tính USB, thẻ nhớ), đủ dung lượng; sai thì báo lỗi rồi khởi động lại, không xoá gì.

  Tham số:
    -CauHinh <file>       file cấu hình (mặc định cau-hinh\CauHinh.json, ghi đè bằng CauHinh.local.json nếu có)
    -Ra <thư mục>         nơi ghi (mặc định out\unattend)
    -DiskId <số>          ghi cố định số ổ cho bản xoá ổ (máy ảo, USB không phải Ventoy). Bỏ trống: biến Ventoy
                          $$VT_WINDOWS_DISK_1ST_NONUSB$$ (ổ đầu tiên không phải USB, Ventoy điền lúc khởi động)
    -MatKhauFile <file>   dòng đầu là mật khẩu cho taiKhoan.cheDo = tu-dong; không có thì hỏi (gõ hai lần)
    -KhongMatKhau         taiKhoan.cheDo = tu-dong mà để trống mật khẩu
  Mã thoát: 0 xong, 1 lỗi cấu hình hoặc lỗi ghi file.
#>
[CmdletBinding()]
param(
    [string]$CauHinh = '',
    [string]$Ra = '',
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
if (-not $CauHinh) { $CauHinh = Join-Path $repo 'cau-hinh\CauHinh.json' }
if (-not $Ra) { $Ra = Join-Path $repo 'out\unattend' }

$script:NsU = 'urn:schemas-microsoft-com:unattend'
$script:NsWcm = 'http://schemas.microsoft.com/WMIConfig/2002/State'
$script:NsExt = 'https://github.com/NovWyatt/AutoSetup_Win'
$script:GuardFile = 'X:\as-kt.vbs'
$script:MaxPath = 255   # Path của RunSynchronousCommand tối đa 259 ký tự; chừa lề

$script:Variants = @(
    [pscustomobject]@{ Ten = '1_Chon-o-bang-tay'; O = 'tay'; SauCai = $true; MoTa = 'Tự chọn ổ, phân vùng trong Windows Setup (an toàn, không tự xoá gì); chạy bước sau cài từ USB.' }
    [pscustomobject]@{ Ten = '2_Chon-o-bang-tay_Chi-Windows'; O = 'tay'; SauCai = $false; MoTa = 'Tự chọn ổ, phân vùng; chỉ cài Windows, không chạy bước sau cài.' }
    [pscustomobject]@{ Ten = '3_XOA-SACH-o_1-phan-vung'; O = 'xoa-1'; SauCai = $true; MoTa = 'XOÁ SẠCH ổ trong duy nhất của máy, tạo một phân vùng C; chạy bước sau cài.' }
    [pscustomobject]@{ Ten = '4_XOA-SACH-o_1-phan-vung_Chi-Windows'; O = 'xoa-1'; SauCai = $false; MoTa = 'XOÁ SẠCH ổ, một phân vùng C; chỉ cài Windows.' }
    [pscustomobject]@{ Ten = '5_XOA-SACH-o_chia-C-D'; O = 'xoa-cd'; SauCai = $true; MoTa = 'XOÁ SẠCH ổ trong duy nhất, chia C và D (dữ liệu); chạy bước sau cài.' }
    [pscustomobject]@{ Ten = '6_XOA-SACH-o_chia-C-D_Chi-Windows'; O = 'xoa-cd'; SauCai = $false; MoTa = 'XOÁ SẠCH ổ, chia C và D; chỉ cài Windows.' }
)

function Wait-Close {
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host '  Bấm Enter để đóng cửa sổ')
}

function ConvertTo-XmlText { param([string]$Text) return [Security.SecurityElement]::Escape($Text) }

function New-El {
    # Phần tử trong namespace unattend; -Add thêm wcm:action="add".
    param([xml]$Doc, [string]$Name, $Text = $null, [switch]$Add)
    $e = $Doc.CreateElement($Name, $script:NsU)
    if ($Add) {
        $a = $Doc.CreateAttribute('wcm', 'action', $script:NsWcm)
        $a.Value = 'add'
        [void]$e.Attributes.Append($a)
    }
    if ($null -ne $Text) { $e.InnerText = [string]$Text }
    return $e
}

function Add-Children {
    # Thêm các phần tử con dạng @(@('Ten', 'giá trị'), ...).
    param($Parent, [xml]$Doc, [object[]]$Pairs)
    foreach ($p in $Pairs) { [void]$Parent.AppendChild((New-El $Doc $p[0] $p[1])) }
}

function Get-GuardLines {
    # Các dòng của KiemTraO.vbs nhúng vào lệnh echo: bỏ dòng trống, dòng chú thích; chặn ký tự cmd hiểu khác.
    $lines = @(Get-Content -LiteralPath (Join-Path $repo 'unattend\KiemTraO.vbs') -Encoding UTF8 |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("'") })
    foreach ($l in $lines) {
        if ($l -match '[&|<>^%]') { throw "unattend\KiemTraO.vbs có ký tự cmd không ghi được bằng echo (& | < > ^ %): $l" }
    }
    return , $lines
}

function Get-Password {
    # Mật khẩu cho tài khoản tự tạo. Trả chuỗi (có thể rỗng).
    if ($KhongMatKhau) { return '' }
    if ($MatKhauFile) {
        if (-not (Test-Path -LiteralPath $MatKhauFile)) { throw "Không thấy file mật khẩu $MatKhauFile" }
        return [string](@(Get-Content -LiteralPath $MatKhauFile -Encoding UTF8 -TotalCount 1)[0])
    }
    if ([Console]::IsInputRedirected) { throw 'taiKhoan.cheDo = tu-dong: cần -MatKhauFile hoặc -KhongMatKhau khi chạy không có bàn phím.' }
    for ($i = 0; $i -lt 3; $i++) {
        $a = Read-Host '  Mật khẩu cho tài khoản (Enter để trống)' -AsSecureString
        $b = Read-Host '  Gõ lại mật khẩu' -AsSecureString
        $pa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $pb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
        if ($pa -ceq $pb) { return $pa }
        Write-Warn 'Hai lần gõ không khớp, gõ lại.'
    }
    throw 'Gõ mật khẩu không khớp ba lần.'
}

function Get-ObscuredPassword {
    # Cách "ẩn" mật khẩu của Windows SIM: base64 của UTF-16LE (mật khẩu + "Password"). Chỉ che, KHÔNG mã hoá.
    param([string]$Password)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Password + 'Password'))
}

function New-VariantXml {
    param($Cfg, $V, [string[]]$GuardLines, [string]$Password, [hashtable]$Sources)
    $cv = { param($p, $d = $null) Get-ConfigValue $Cfg $p $d }
    $accountAuto = (& $cv 'taiKhoan.cheDo') -eq 'tu-dong'
    $tenMay = [string](& $cv 'tenMay' '*')
    $map = [ordered]@{
        BIEN_THE     = $V.Ten
        TAO_LUC      = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        GIAO_DIEN    = & $cv 'ngonNgu.giaoDien'
        BAN_PHIM     = & $cv 'ngonNgu.banPhim'
        HE_THONG     = & $cv 'ngonNgu.heThong'
        DINH_DANG    = & $cv 'ngonNgu.dinhDang'
        MUI_GIO      = & $cv 'ngonNgu.muiGio'
        TEN_MAY      = $(if ($tenMay -in '*', 'hoi') { '*' } else { $tenMay })
        AN_TAI_KHOAN = $(if ($accountAuto) { 'true' } else { 'false' })
        AN_WIFI      = $(if ((& $cv 'oobe.hienWifi' $true) -eq $true) { 'false' } else { 'true' })
        KEY          = ''
        KEY_UI       = 'OnError'
    }
    $text = $Sources.Khung
    foreach ($k in $map.Keys) { $text = $text.Replace("{{$k}}", (ConvertTo-XmlText ([string]$map[$k]))) }
    if ($text -match '\{\{[A-Z_]+\}\}') { throw "khung.xml còn chỗ chưa điền: $($Matches[0])" }

    $doc = New-Object Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    $doc.LoadXml($text)
    $ns = New-Object Xml.XmlNamespaceManager $doc.NameTable
    $ns.AddNamespace('u', $script:NsU)
    $ns.AddNamespace('e', $script:NsExt)
    $setup = $doc.SelectSingleNode("//u:settings[@pass='windowsPE']/u:component[@name='Microsoft-Windows-Setup']", $ns)

    # ---- bản quyền: bios = không ghi key, Setup dùng key trong BIOS/UEFI, không có thì hỏi (OnError)
    $keyEl = $setup.SelectSingleNode('u:UserData/u:ProductKey/u:Key', $ns)
    $uiEl = $setup.SelectSingleNode('u:UserData/u:ProductKey/u:WillShowUI', $ns)
    switch (& $cv 'banQuyen.cheDo') {
        'bios' { [void]$keyEl.ParentNode.RemoveChild($keyEl); $uiEl.InnerText = 'OnError' }
        'hoi' { $keyEl.InnerText = '00000-00000-00000-00000-00000'; $uiEl.InnerText = 'Always' }
        'key-chung' { $keyEl.InnerText = $script:GenericKeys[[string](& $cv 'banQuyen.phienBanWindows')].Key; $uiEl.InnerText = 'OnError' }
    }

    # ---- lệnh chạy trong WinPE: bỏ kiểm tra phần cứng, kiểm tra ổ trước khi xoá
    $run = $setup.SelectSingleNode('u:RunSynchronous', $ns)
    $cmds = New-Object System.Collections.Generic.List[object]
    if ((& $cv 'oobe.boQuaKiemTraPhanCung' $true) -eq $true) {
        foreach ($n in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck') {
            $cmds.Add(@("reg.exe add `"HKLM\SYSTEM\Setup\LabConfig`" /v $n /t REG_DWORD /d 1 /f", "Bo kiem tra $n"))
        }
    }
    $disk = if ($DiskId -ne '') { $DiskId } else { '$$VT_WINDOWS_DISK_1ST_NONUSB$$' }
    if ($V.O -ne 'tay') {
        $minGB = if ($V.O -eq 'xoa-cd') { [int](& $cv 'oDia.dungLuongC_GB') + 20 } else { [int](& $cv 'oDia.toiThieuGB') }
        $first = $true
        foreach ($l in $GuardLines) {
            $redir = if ($first) { '>' } else { '>>' }
            $cmds.Add(@(('cmd.exe /c "{0}{1} echo {2}"' -f $redir, $script:GuardFile, $l), 'Ghi script kiem tra o'))
            $first = $false
        }
        $cmds.Add(@(('cmd.exe /c "cscript.exe //nologo //E:vbscript {0} {1} {2} || wpeutil.exe reboot"' -f $script:GuardFile, $disk, $minGB), 'Kiem tra o truoc khi xoa'))
    }
    $order = 1
    foreach ($c in $cmds) {
        if ($c[0].Length -gt $script:MaxPath) { throw "Lệnh WinPE dài quá $($script:MaxPath) ký tự ($($c[0].Length)): $($c[0])" }
        $rc = New-El $doc 'RunSynchronousCommand' -Add
        Add-Children $rc $doc @(@('Order', $order), @('Description', $c[1]), @('Path', $c[0]))
        [void]$run.AppendChild($rc)
        $order++
    }
    if (-not $cmds.Count) { [void]$setup.RemoveChild($run) }

    # ---- chia ổ (chỉ bản xoá ổ): GPT, EFI + MSR + Windows (+ DATA)
    if ($V.O -ne 'tay') {
        $dc = New-El $doc 'DiskConfiguration'
        $d = New-El $doc 'Disk' -Add
        Add-Children $d $doc @(@('DiskID', $disk), @('WillWipeDisk', 'true'))
        $cp = New-El $doc 'CreatePartitions'
        $parts = @(@('EFI', [int](& $cv 'oDia.heThongMB')), @('MSR', 16))
        if ($V.O -eq 'xoa-cd') { $parts += , @('Primary', ([int](& $cv 'oDia.dungLuongC_GB') * 1024)); $parts += , @('Primary', 'extend') }
        else { $parts += , @('Primary', 'extend') }
        $i = 1
        foreach ($p in $parts) {
            $e = New-El $doc 'CreatePartition' -Add
            $kv = @(@('Order', $i), @('Type', $p[0]))
            if ($p[1] -eq 'extend') { $kv += , @('Extend', 'true') } else { $kv += , @('Size', $p[1]) }
            Add-Children $e $doc $kv
            [void]$cp.AppendChild($e)
            $i++
        }
        [void]$d.AppendChild($cp)
        $mp = New-El $doc 'ModifyPartitions'
        $mods = @(
            @(@('Order', 1), @('PartitionID', 1), @('Label', 'System'), @('Format', 'FAT32')),
            @(@('Order', 2), @('PartitionID', 2)),
            @(@('Order', 3), @('PartitionID', 3), @('Label', 'Windows'), @('Letter', 'C'), @('Format', 'NTFS'))
        )
        # Phân vùng dữ liệu không gán chữ ổ ở đây (WinPE có thể đang dùng D cho USB); bước sau cài đổi nó thành D.
        if ($V.O -eq 'xoa-cd') { $mods += , @(@('Order', 4), @('PartitionID', 4), @('Label', 'DATA'), @('Format', 'NTFS')) }
        foreach ($m in $mods) {
            $e = New-El $doc 'ModifyPartition' -Add
            Add-Children $e $doc $m
            [void]$mp.AppendChild($e)
        }
        [void]$d.AppendChild($mp)
        [void]$dc.AppendChild($d)
        [void]$dc.AppendChild((New-El $doc 'WillShowUI' 'OnError'))
        [void]$setup.AppendChild($dc)

        $ii = New-El $doc 'ImageInstall'
        $os = New-El $doc 'OSImage'
        $to = New-El $doc 'InstallTo'
        Add-Children $to $doc @(@('DiskID', $disk), @('PartitionID', 3))
        [void]$os.AppendChild($to)
        [void]$os.AppendChild((New-El $doc 'WillShowUI' 'OnError'))
        [void]$ii.AppendChild($os)
        [void]$setup.AppendChild($ii)
    }

    # ---- tài khoản tự tạo
    if ($accountAuto) {
        $shell = $doc.SelectSingleNode("//u:settings[@pass='oobeSystem']/u:component[@name='Microsoft-Windows-Shell-Setup']", $ns)
        $name = [string](& $cv 'taiKhoan.ten')
        $display = [string](& $cv 'taiKhoan.tenHienThi' '')
        if (-not $display) { $display = $name }
        $pwValue = if ($Password) { Get-ObscuredPassword $Password } else { '' }
        $pwPlain = if ($Password) { 'false' } else { 'true' }
        $ua = New-El $doc 'UserAccounts'
        $la = New-El $doc 'LocalAccounts'
        $acc = New-El $doc 'LocalAccount' -Add
        Add-Children $acc $doc @(@('Name', $name), @('DisplayName', $display), @('Group', 'Administrators'))
        $pw = New-El $doc 'Password'
        Add-Children $pw $doc @(@('Value', $pwValue), @('PlainText', $pwPlain))
        [void]$acc.AppendChild($pw)
        [void]$la.AppendChild($acc)
        [void]$ua.AppendChild($la)
        [void]$shell.InsertBefore($ua, $shell.SelectSingleNode('u:FirstLogonCommands', $ns))
        if ((& $cv 'taiKhoan.tuDangNhap' $true) -eq $true) {
            $al = New-El $doc 'AutoLogon'
            Add-Children $al $doc @(@('Username', $name), @('Enabled', 'true'), @('LogonCount', 1))
            $pw2 = New-El $doc 'Password'
            Add-Children $pw2 $doc @(@('Value', $pwValue), @('PlainText', $pwPlain))
            [void]$al.AppendChild($pw2)
            [void]$shell.InsertBefore($al, $shell.SelectSingleNode('u:FirstLogonCommands', $ns))
        }
    }

    # ---- script nhúng (giải nén ra C:\Windows\Setup\Scripts ở bước specialize)
    $ext = $doc.SelectSingleNode('//e:Extensions', $ns)
    $ext.SelectSingleNode('e:ExtractScript', $ns).InnerText = $Sources.GiaiNen
    $info = [ordered]@{
        bienThe    = $V.Ten
        sauCai     = [bool]$V.SauCai
        tenMayNhap = $(if ($tenMay -eq 'hoi') { '$$TEN_MAY$$' } else { '' })
        goBo       = & $cv 'goBo'
        tinhChinh  = & $cv 'tinhChinh'
        oobe       = & $cv 'oobe'
        taoLuc     = (Get-Date).ToString('s')
    }
    $files = [ordered]@{
        'C:\Windows\Setup\Scripts\AutoSetup.json'  = (ConvertTo-JsonText $info)
        'C:\Windows\Setup\Scripts\Specialize.ps1'  = $Sources.Specialize
        'C:\Windows\Setup\Scripts\DefaultUser.ps1' = $Sources.DefaultUser
        'C:\Windows\Setup\Scripts\FirstLogon.ps1'  = $Sources.FirstLogon
    }
    foreach ($path in $files.Keys) {
        $f = $doc.CreateElement('File', $script:NsExt)
        $f.SetAttribute('path', $path)
        $f.InnerText = "`n" + $files[$path].Trim() + "`n"
        [void]$ext.AppendChild($f)
    }
    return $doc
}

function Save-Xml {
    param([xml]$Doc, [string]$Path)
    $s = New-Object Xml.XmlWriterSettings
    $s.Indent = $true
    $s.IndentChars = '  '
    $s.Encoding = New-Object Text.UTF8Encoding $false   # Ventoy cần UTF-8 để điền biến
    $s.NewLineChars = "`r`n"
    $s.NewLineHandling = [Xml.NewLineHandling]::Replace
    $w = [Xml.XmlWriter]::Create($Path, $s)
    try { $Doc.Save($w) } finally { $w.Close() }
}

function Test-OneVariablePerLine {
    # Ventoy chỉ điền một biến $$...$$ trên mỗi dòng.
    param([string]$Path)
    $n = 0
    foreach ($l in [IO.File]::ReadAllLines($Path)) {
        $n++
        if (([regex]::Matches($l, '\$\$[A-Za-z0-9_]+\$\$')).Count -gt 1) { throw "Dòng $n của $Path có hơn một biến Ventoy." }
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:AUTOSETUP_TEST_NAP) { return }   # bài thử nạp các hàm rồi tự gọi
try {
    Write-Head 'SINH FILE UNATTEND'
    $cfg = Get-AutoSetupConfig $CauHinh
    $errs = Test-AutoSetupConfig $cfg
    if ($errs.Count) {
        Write-Bad "Cấu hình $CauHinh có lỗi:"
        foreach ($e in $errs) { Write-Sub $e }
        Wait-Close
        exit 1
    }
    if ($DiskId -ne '' -and $DiskId -notmatch '^\d{1,2}$') { throw "-DiskId phải là số ổ (0, 1, ...), không phải '$DiskId'." }
    $password = ''
    if ((Get-ConfigValue $cfg 'taiKhoan.cheDo') -eq 'tu-dong') {
        Write-Info ('Tài khoản tự tạo: {0}' -f (Get-ConfigValue $cfg 'taiKhoan.ten'))
        $password = Get-Password
        if (-not $password) { Write-Warn 'Tài khoản không có mật khẩu: ai ngồi vào máy cũng vào được. Đổi mật khẩu sau khi giao máy.' }
        else { Write-Warn 'Mật khẩu nằm trong file unattend dạng base64 (che, không mã hoá). Giữ USB cẩn thận; Windows xoá bản trên máy ở lần đăng nhập đầu.' }
    }
    $src = @{
        Khung       = [IO.File]::ReadAllText((Join-Path $repo 'unattend\khung.xml'), [Text.Encoding]::UTF8)
        GiaiNen     = [IO.File]::ReadAllText((Join-Path $repo 'unattend\scripts\GiaiNen.ps1'), [Text.Encoding]::UTF8).Trim()
        Specialize  = [IO.File]::ReadAllText((Join-Path $repo 'unattend\scripts\Specialize.ps1'), [Text.Encoding]::UTF8)
        DefaultUser = [IO.File]::ReadAllText((Join-Path $repo 'unattend\scripts\DefaultUser.ps1'), [Text.Encoding]::UTF8)
        FirstLogon  = [IO.File]::ReadAllText((Join-Path $repo 'unattend\scripts\FirstLogon.ps1'), [Text.Encoding]::UTF8)
    }
    foreach ($k in 'Specialize', 'DefaultUser', 'FirstLogon', 'GiaiNen') {
        if ($src[$k] -match '\$\$') { throw "Script nhúng $k có chuỗi `$`$ (Ventoy sẽ hiểu là biến cần hỏi)." }
    }
    $guard = Get-GuardLines
    if (-not (Test-Path -LiteralPath $Ra)) { New-Item -ItemType Directory -Path $Ra -Force | Out-Null }
    Get-ChildItem -LiteralPath $Ra -Filter '*.xml' -File | Remove-Item -Force
    $list = @()
    foreach ($var in $script:Variants) {
        $doc = New-VariantXml -Cfg $cfg -V $var -GuardLines $guard -Password $password -Sources $src
        $file = Join-Path $Ra ($var.Ten + '.xml')
        Save-Xml $doc $file
        Test-OneVariablePerLine $file
        $list += [ordered]@{ tep = $var.Ten + '.xml'; moTa = $var.MoTa; xoaO = ($var.O -ne 'tay'); sauCai = [bool]$var.SauCai }
        Write-Ok "$($var.Ten).xml"
    }
    Write-JsonFile (Join-Path $Ra 'DanhSach.json') ([ordered]@{ taoLuc = (Get-Date).ToString('s'); diskId = $(if ($DiskId -ne '') { $DiskId } else { 'ventoy' }); tep = $list })
    Write-Line ''
    Write-Info "Đã ghi $($list.Count) file vào $Ra"
    if ($DiskId -eq '') { Write-Info 'Bản XOÁ SẠCH ổ dùng biến của Ventoy: chỉ dùng được khi khởi động bằng USB Ventoy.' }
    else { Write-Warn "Bản XOÁ SẠCH ổ ghi cố định ổ số $DiskId." }
    Wait-Close
    exit 0
} catch {
    Write-Bad $_.Exception.Message
    Wait-Close
    exit 1
}
