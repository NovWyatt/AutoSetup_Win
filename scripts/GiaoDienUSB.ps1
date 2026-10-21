<#
  AutoSetup_Win - giao diện tạo USB cài Windows: cài hoặc cập nhật Ventoy, chép ISO, sửa các cấu hình chính, rồi chép
  AutoSetup lên USB (gọi TaoUSB.ps1). Mở bằng TAO_USB_GIAO_DIEN.bat; tự xin quyền quản trị (cần để cài Ventoy).
  Việc lâu (tải và cài Ventoy, chép ISO, TaoUSB) chạy trong tiến trình riêng (ViecNenUSB.ps1), cửa sổ không bị đơ.

  Tham số:
    -KhongNangQuyen      mở không xin quyền quản trị (không cài được Ventoy)
    -AnhRa <file.png>    dựng cửa sổ, lưu ảnh thẻ -The rồi thoát (kiểm giao diện không cần bấm)
    -The <0-3>           thẻ mở sẵn: 0 USB, 1 ISO, 2 Cấu hình, 3 Tạo USB
    -O <ổ hoặc thư mục>  chọn sẵn USB đích
    -ChiNap              chỉ dựng cửa sổ và hàm rồi dừng, không hiện (bài thử chấm nguồn script này để bấm thay)
  Bài thử đặt AUTOSETUP_CAUHINH (thư mục cấu hình thay cau-hinh), AUTOSETUP_OUT (TaoUSB ghi unattend ra đó).
#>
param([switch]$KhongNangQuyen, [string]$AnhRa = '', [int]$The = 0, [string]$O = '', [switch]$ChiNap)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\CauHinh.ps1')
. (Join-Path $PSScriptRoot 'lib\USB.ps1')
. (Join-Path $repo 'sau-cai\lib\Chung.ps1')

function Join-CommandLine {
    # Ghép tham số thành dòng lệnh Windows (bọc ngoặc kép khi có dấu cách; gấp đôi \ đứng trước " hoặc cuối chuỗi,
    # vd -O "E:\" phải thành "E:\\" kẻo \" nuốt dấu ngoặc).
    param([string[]]$Arguments)
    return (@($Arguments | ForEach-Object {
                if ($_ -ne '' -and $_ -notmatch '[\s"]') { $_ }
                else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
            }) -join ' ')
}

$self = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath)
if ($O) { $self += @('-O', $O) }
if (-not $KhongNangQuyen -and -not $AnhRa -and -not $ChiNap -and -not (Test-IsAdmin)) {
    try {
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList (Join-CommandLine $self)
        exit 0
    } catch { }   # bấm No ở hộp UAC: vẫn mở, chỉ không cài được Ventoy
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $self += '-KhongNangQuyen'
    if ($AnhRa) { $self += @('-AnhRa', $AnhRa, '-The', [string]$The) }
    Start-Process powershell.exe -ArgumentList (Join-CommandLine $self) -Wait -WindowStyle Hidden
    exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$script:IsAdmin = Test-IsAdmin
$script:CfgDir = if ($env:AUTOSETUP_CAUHINH) { $env:AUTOSETUP_CAUHINH } else { Join-Path $repo 'cau-hinh' }
$script:CfgPath = Join-Path $script:CfgDir 'CauHinh.json'
$script:LocalPath = Join-Path $script:CfgDir 'CauHinh.local.json'
$script:Root = ''
$script:DiskNo = $null
$script:Job = $null
$script:RefreshLeft = 0
$script:Apps = $null
$script:AppsSource = ''
$script:TuTraLoi = ''   # bài thử đặt 'Yes'/'No': hộp thoại trả luôn, không hiện

$script:BanQuyen = [ordered]@{
    'bios'      = 'Lấy key trong BIOS (máy có Windows bản quyền sẵn)'
    'hoi'       = 'Hỏi key khi cài'
    'key-chung' = 'Key cài đặt chung: cài được, KHÔNG kích hoạt'
}
$script:TaiKhoan = [ordered]@{
    'hoi'     = 'Hỏi khi cài (màn hình thiết lập đầu tiên)'
    'tu-dong' = 'Tự tạo tài khoản quản trị'
}
$script:MacDinh = @(
    '0. Cài thường, không dùng AutoSetup'
    '1. Tự chọn ổ (không xoá gì)'
    '2. Tự chọn ổ, chỉ cài Windows'
    '3. XOÁ SẠCH ổ, một phân vùng C'
    '4. XOÁ SẠCH ổ, một phân vùng C, chỉ cài Windows'
    '5. XOÁ SẠCH ổ, chia C và D'
    '6. XOÁ SẠCH ổ, chia C và D, chỉ cài Windows'
)

# ---------------------------------------------------------------- cửa sổ
[xml]$xaml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GiaoDienUSB.xaml'), [Text.Encoding]::UTF8)
$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$nsm = New-Object Xml.XmlNamespaceManager $xaml.NameTable
$nsm.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@x:Name]', $nsm)) {
    $name = $n.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $ui[$name] = $win.FindName($name)
}

function Add-Log {
    param([string]$Text)
    $ui.txtNhatKy.AppendText("$Text`r`n")
    $ui.txtNhatKy.ScrollToEnd()
}

function Set-Status { param([string]$Text) $ui.txtTrangThai.Text = $Text }

function Show-Message {
    param([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK', [string]$Default = 'OK')
    if ($script:TuTraLoi) { Add-Log "[hộp thoại] $($Text -replace '\s+', ' ') -> $($script:TuTraLoi)"; return $script:TuTraLoi }
    return [string][Windows.MessageBox]::Show($win, $Text, 'AutoSetup_Win', $Buttons, $Icon, $Default)
}

# ---------------------------------------------------------------- việc chạy nền
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$refreshTimer = New-Object Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromMilliseconds(1500)

function Start-Background {
    # Chạy script PowerShell trong tiến trình riêng (dùng chung cửa sổ console ẩn của giao diện), đầu ra ghi file tạm,
    # bộ đếm giờ đọc dần vào nhật ký. Stdin là file rỗng: lỡ script hỏi gì thì nhận ngay dòng trống thay vì treo.
    param([string]$Title, [string]$Script, [string[]]$Arguments, [scriptblock]$OnDone, [string[]]$TempFiles = @())
    if ($script:Job) { return }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $base = Join-Path ([IO.Path]::GetTempPath()) "AutoSetup-GiaoDien-$id"
    $in = "$base.in"; [IO.File]::WriteAllText($in, '')
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
    $p = Start-Process powershell.exe -ArgumentList (Join-CommandLine $all) -NoNewWindow -PassThru `
        -RedirectStandardOutput "$base.out" -RedirectStandardError "$base.err" -RedirectStandardInput $in
    $null = $p.Handle   # giữ handle để đọc được ExitCode sau khi tiến trình thoát
    $script:Job = @{ Proc = $p; Base = $base; Pos = 0; OnDone = $OnDone; Temp = @($TempFiles + $in + "$base.out" + "$base.err"); Title = $Title }
    $ui.pbTienDo.Value = 0
    $ui.pbTienDo.IsIndeterminate = $true
    Set-Status "$Title..."
    Add-Log ''
    Add-Log "== $Title"
    Update-Buttons
    $timer.Start()
}

function Read-NewLines {
    # Dòng mới (đủ dòng) trong file đầu ra từ vị trí đã đọc; $Final thì lấy hết.
    param([hashtable]$Job, [string]$Path, [bool]$Final)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -le $Job.Pos) { return @() }
        $fs.Position = $Job.Pos
        $buf = New-Object byte[] ([int]($fs.Length - $Job.Pos))
        $n = $fs.Read($buf, 0, $buf.Length)
    } finally { $fs.Dispose() }
    $end = if ($Final) { $n } else { [Array]::LastIndexOf($buf, [byte]10, $n - 1) + 1 }
    if ($end -le 0) { return @() }
    $Job.Pos += $end
    $text = [Text.Encoding]::UTF8.GetString($buf, 0, $end).TrimStart([char]0xFEFF)
    $lines = @($text -split "`r?`n")
    if ($lines.Count -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -SkipLast 1) }
    return $lines
}

function Receive-Background {
    $j = $script:Job
    if (-not $j) { $timer.Stop(); return }
    $exited = $j.Proc.HasExited
    foreach ($line in (Read-NewLines $j "$($j.Base).out" $exited)) {
        if ($line -match '^##TIENDO (\d+)') { $ui.pbTienDo.IsIndeterminate = $false; $ui.pbTienDo.Value = [int]$Matches[1] }
        else { Add-Log $line }
    }
    if (-not $exited) { return }
    $err = "$($j.Base).err"
    if ((Test-Path -LiteralPath $err) -and (Get-Item -LiteralPath $err).Length) {
        foreach ($line in [IO.File]::ReadAllLines($err, [Text.Encoding]::UTF8)) { if ($line.Trim()) { Add-Log "[lỗi] $line" } }
    }
    $code = $j.Proc.ExitCode
    foreach ($f in $j.Temp) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    $script:Job = $null
    $timer.Stop()
    $ui.pbTienDo.IsIndeterminate = $false
    if ($code -eq 0) { $ui.pbTienDo.Value = 100; Set-Status "$($j.Title): xong." }
    else { Set-Status "$($j.Title): lỗi (mã $code), xem nhật ký bên dưới." }
    Update-Buttons
    if ($j.OnDone) { & $j.OnDone $code }
}
$timer.Add_Tick({ Receive-Background })

# ---------------------------------------------------------------- USB, ISO
function Update-Buttons {
    $busy = $null -ne $script:Job
    $d = $ui.lvUsb.SelectedItem
    $ui.btnLamMoiUsb.IsEnabled = -not $busy
    $ui.btnChonThuMuc.IsEnabled = -not $busy
    $ui.btnCaiVentoy.IsEnabled = (-not $busy) -and $d -and $script:IsAdmin
    $ui.btnCapNhatVentoy.IsEnabled = (-not $busy) -and $d -and $d.Ventoy -and $script:IsAdmin
    foreach ($b in 'btnThemIso', 'btnTao') { $ui[$b].IsEnabled = (-not $busy) -and [bool]$script:Root }
    $ui.btnMoUsb.IsEnabled = [bool]$script:Root
    $ui.btnLamMoiIso.IsEnabled = -not $busy
    $ui.btnLuuCauHinh.IsEnabled = -not $busy
}

function Set-Target {
    param([string]$Root, [string]$Text)
    $script:Root = $Root
    $ui.txtDich.Text = $Text
    Update-IsoList
    Update-Buttons
}

function Update-UsbList {
    $list = @(ConvertTo-UsbDiskList (Get-DiskInventory))
    $keep = $script:DiskNo
    $ui.lvUsb.ItemsSource = $list
    $match = if ($null -ne $keep) { @($list | Where-Object { $_.So -eq $keep }) | Select-Object -First 1 } else { $null }
    if ($match) { $ui.lvUsb.SelectedItem = $match }
    elseif (-not $script:Root -and $list.Count -eq 1) { $ui.lvUsb.SelectedIndex = 0 }
    if (-not $list.Count) { Set-Status 'Chưa thấy USB nào: cắm USB rồi bấm Làm mới.' }
    Update-Buttons
    return $list
}

function Select-Usb {
    $d = $ui.lvUsb.SelectedItem
    if (-not $d) { Update-Buttons; return }
    $script:DiskNo = $d.So
    if ($d.Ventoy -and $d.ODuLieu) { Set-Target $d.ODuLieu ("USB đích: {0}  ({1}, {2}, đã có Ventoy)" -f $d.ODuLieu, $d.Ten, $d.KichThuocChu) }
    elseif ($d.Ventoy) { Set-Target '' "USB $($d.Ten) có Ventoy nhưng phân vùng dữ liệu chưa có chữ ổ: rút ra cắm lại rồi bấm Làm mới." }
    else { Set-Target '' "USB $($d.Ten) chưa có Ventoy: bấm Cài Ventoy (xoá sạch USB) trước." }
}

function Update-IsoList {
    $pattern = [string](Get-ConfigValue (Get-AutoSetupConfig $script:CfgPath) 'ventoy.locTenIso' '(?i)win')
    $ui.lvIso.ItemsSource = @(Find-IsoFiles $script:Root $pattern)
}

function Start-Ventoy {
    param([string]$Lenh)
    $d = $ui.lvUsb.SelectedItem
    if (-not $d) { return }
    if ($Lenh -eq 'I') {
        $what = "Ổ số $($d.So): $($d.Ten), $($d.KichThuocChu)"
        if ((Show-Message "Cài Ventoy sẽ XOÁ SẠCH mọi dữ liệu trên:`n`n    $what`n`nTiếp tục?" 'Warning' 'YesNo' 'No') -ne 'Yes') { return }
        if ((Show-Message "Lần cuối: xoá sạch $($d.Ten) ($($d.KichThuocChu))?" 'Warning' 'YesNo' 'No') -ne 'Yes') { return }
    }
    $a = @('-Viec', 'ventoy', '-Lenh', $Lenh, '-So', [string]$d.So, '-KichThuoc', [string][double]$d.KichThuoc, '-Ten', $d.Ten)
    if ($ui.cbGpt.IsChecked) { $a += '-Gpt' }
    if (-not $ui.cbSecureBoot.IsChecked) { $a += '-KhongSecureBoot' }
    $title = if ($Lenh -eq 'I') { 'Cài Ventoy' } else { 'Cập nhật Ventoy' }
    Start-Background -Title $title -Script (Join-Path $PSScriptRoot 'ViecNenUSB.ps1') -Arguments $a -OnDone {
        param($code)
        # Windows cần vài giây mới gán chữ ổ cho phân vùng Ventoy mới: làm mới vài lần.
        $script:RefreshLeft = 6
        $refreshTimer.Start()
    }
}
$refreshTimer.Add_Tick({
        $script:RefreshLeft--
        [void](Update-UsbList)
        Select-Usb
        if ($script:Root -or $script:RefreshLeft -le 0) { $refreshTimer.Stop() }
    })

function Add-Iso {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'File ISO (*.iso)|*.iso'
    $dlg.Multiselect = $true
    $dlg.Title = 'Chọn ISO để chép lên USB'
    if (-not $dlg.ShowDialog($win)) { return }
    $a = @('-Viec', 'chep', '-Nguon', ($dlg.FileNames -join '|'), '-Dich', $script:Root)
    Start-Background -Title 'Chép ISO' -Script (Join-Path $PSScriptRoot 'ViecNenUSB.ps1') -Arguments $a -OnDone { param($code) Update-IsoList }
}

function Select-Folder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Chọn ổ hoặc thư mục đích (gốc phân vùng dữ liệu Ventoy, hoặc thư mục để thử)'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $p = $dlg.SelectedPath
    if ($p.TrimEnd('\') -ieq $env:SystemDrive) { Show-Message 'Không dùng ổ Windows làm đích.' 'Warning' | Out-Null; return }
    $script:DiskNo = $null
    $ui.lvUsb.SelectedItem = $null
    Set-Target $p "Đích: $p  (chọn tay, không kiểm Ventoy)"
}

# ---------------------------------------------------------------- cấu hình
function Add-ComboItems {
    param($Combo, $Map)
    foreach ($k in $Map.Keys) {
        $it = New-Object Windows.Controls.ComboBoxItem
        $it.Content = $Map[$k]; $it.Tag = $k
        [void]$Combo.Items.Add($it)
    }
}

function Select-ComboTag {
    param($Combo, $Tag)
    foreach ($it in $Combo.Items) { if ([string]$it.Tag -eq [string]$Tag) { $Combo.SelectedItem = $it; return } }
    $Combo.SelectedIndex = 0
}

function Get-ComboTag {
    param($Combo)
    if ($Combo.SelectedItem) { return [string]$Combo.SelectedItem.Tag }
    return ''
}

function Update-FormState {
    $auto = (Get-ComboTag $ui.cboTaiKhoan) -eq 'tu-dong'
    foreach ($c in 'txtTen', 'txtTenHienThi', 'pwdMatKhau', 'cbTuDangNhap') { $ui[$c].IsEnabled = $auto }
    $ui.cboPhienBan.IsEnabled = (Get-ComboTag $ui.cboBanQuyen) -eq 'key-chung'
    $ui.txtTenMay.IsEnabled = [bool]$ui.rbTenCoDinh.IsChecked
}

function Import-ConfigForm {
    $cfg = Get-AutoSetupConfig $script:CfgPath
    $v = { param($p, $d) Get-ConfigValue $cfg $p $d }
    Select-ComboTag $ui.cboBanQuyen (& $v 'banQuyen.cheDo' 'bios')
    Select-ComboTag $ui.cboPhienBan (& $v 'banQuyen.phienBanWindows' 'pro')
    Select-ComboTag $ui.cboTaiKhoan (& $v 'taiKhoan.cheDo' 'hoi')
    $ui.txtTen.Text = [string](& $v 'taiKhoan.ten' 'Admin')
    $ui.txtTenHienThi.Text = [string](& $v 'taiKhoan.tenHienThi' '')
    $ui.cbTuDangNhap.IsChecked = [bool](& $v 'taiKhoan.tuDangNhap' $true)
    $tm = [string](& $v 'tenMay' '*')
    $ui.rbTenNgauNhien.IsChecked = $tm -eq '*'
    $ui.rbTenHoi.IsChecked = $tm -eq 'hoi'
    $ui.rbTenCoDinh.IsChecked = $tm -notin '*', 'hoi'
    $ui.txtTenMay.Text = $(if ($tm -notin '*', 'hoi') { $tm } else { '' })
    $ui.txtDungLuongC.Text = [string](& $v 'oDia.dungLuongC_GB' 150)
    $ui.cboMacDinh.SelectedIndex = [Math]::Min(6, [Math]::Max(0, [int](& $v 'ventoy.macDinh' 1)))
    $ui.txtChoGiay.Text = [string](& $v 'ventoy.choChonGiay' 15)
    $map = @{ cbUngDung = 'ungDung'; cbOffice = 'office'; cbDriver = 'driver'; cbCapNhat = 'capNhatWindows'; cbODuLieu = 'oDuLieuLaD'; cbTuKhoiDongLai = 'tuKhoiDongLai' }
    foreach ($k in $map.Keys) { $ui[$k].IsChecked = [bool](& $v "sauCai.$($map[$k])" $false) }

    $script:AppsSource = Join-Path $script:CfgDir 'UngDung.local.json'
    if (-not (Test-Path -LiteralPath $script:AppsSource)) { $script:AppsSource = Join-Path $script:CfgDir 'UngDung.json' }
    $script:Apps = Read-JsonFile $script:AppsSource
    $ui.lbUngDung.Items.Clear()
    foreach ($a in @($script:Apps.ungDung)) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Content = [string]$a.ten; $cb.Tag = [string]$a.khoa; $cb.IsChecked = $a.macDinh -eq $true
        if ($a.ghiChu) { $cb.ToolTip = [string]$a.ghiChu }
        [void]$ui.lbUngDung.Items.Add($cb)
    }
    $ui.txtCauHinh.Text = $(if (Test-Path -LiteralPath $script:LocalPath) { 'Đang dùng cau-hinh\CauHinh.local.json' } else { 'Đang dùng cấu hình mặc định' })
    Update-FormState
}

function Save-ConfigForm {
    # Ghi các ô trên giao diện vào CauHinh.local.json (giữ các khoá khác người dùng tự thêm), danh sách ứng dụng vào
    # UngDung.local.json khi khác bản đang dùng. Mật khẩu không lưu. Trả $true khi đã lưu.
    $errs = New-Object System.Collections.Generic.List[string]
    $int = { param($text, $name) $n = 0; if ([int]::TryParse(([string]$text).Trim(), [ref]$n)) { return $n }; $errs.Add("$name phải là số."); return $null }
    $c = & $int $ui.txtDungLuongC.Text 'Ổ C khi chia C-D'
    $wait = & $int $ui.txtChoGiay.Text 'Giây chờ chọn'
    if ($errs.Count) { Show-Message ($errs -join "`n") 'Warning' | Out-Null; return $false }

    $local = if (Test-Path -LiteralPath $script:LocalPath) { Read-JsonFile $script:LocalPath } else { [pscustomobject]@{} }
    $tenMay = if ($ui.rbTenHoi.IsChecked) { 'hoi' } elseif ($ui.rbTenCoDinh.IsChecked) { $ui.txtTenMay.Text.Trim() } else { '*' }
    $values = [ordered]@{
        'banQuyen.cheDo'          = Get-ComboTag $ui.cboBanQuyen
        'banQuyen.phienBanWindows' = Get-ComboTag $ui.cboPhienBan
        'taiKhoan.cheDo'          = Get-ComboTag $ui.cboTaiKhoan
        'taiKhoan.ten'            = $ui.txtTen.Text.Trim()
        'taiKhoan.tenHienThi'     = $ui.txtTenHienThi.Text.Trim()
        'taiKhoan.tuDangNhap'     = [bool]$ui.cbTuDangNhap.IsChecked
        'tenMay'                  = $tenMay
        'oDia.dungLuongC_GB'      = $c
        'ventoy.macDinh'          = [int]$ui.cboMacDinh.SelectedIndex
        'ventoy.choChonGiay'      = $wait
        'sauCai.ungDung'          = [bool]$ui.cbUngDung.IsChecked
        'sauCai.office'           = [bool]$ui.cbOffice.IsChecked
        'sauCai.driver'           = [bool]$ui.cbDriver.IsChecked
        'sauCai.capNhatWindows'   = [bool]$ui.cbCapNhat.IsChecked
        'sauCai.oDuLieuLaD'       = [bool]$ui.cbODuLieu.IsChecked
        'sauCai.tuKhoiDongLai'    = [bool]$ui.cbTuKhoiDongLai.IsChecked
    }
    foreach ($k in $values.Keys) { $local = Set-ConfigPath $local $k $values[$k] }
    $bad = Test-AutoSetupConfig (Merge-ConfigObject (Read-JsonFile $script:CfgPath) $local)
    if ($wait -lt 0 -or $wait -gt 600) { $bad = @($bad) + 'Giây chờ chọn phải từ 0 đến 600.' }
    if (@($bad).Count) { Show-Message ("Cấu hình chưa đúng:`n`n- " + (@($bad) -join "`n- ")) 'Warning' | Out-Null; return $false }
    Write-JsonFile $script:LocalPath $local

    $chon = @($ui.lbUngDung.Items | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
    $now = @($script:Apps.ungDung | Where-Object { $_.macDinh -eq $true } | ForEach-Object { [string]$_.khoa })
    if (Compare-Object $chon $now) {
        $script:Apps = Set-AppSelection $script:Apps $chon
        $script:AppsSource = Join-Path $script:CfgDir 'UngDung.local.json'
        Write-JsonFile $script:AppsSource $script:Apps
    }
    $ui.txtCauHinh.Text = 'Đã lưu cau-hinh\CauHinh.local.json lúc {0:HH:mm:ss}' -f (Get-Date)
    Update-IsoList
    return $true
}

function Update-Summary {
    $isos = @($ui.lvIso.ItemsSource)
    $win10 = @($isos | Where-Object { $_.Loai -eq 'windows' })
    $lines = @()
    $lines += $(if ($script:Root) { $ui.txtDich.Text } else { 'Chưa chọn USB đích (thẻ 1. USB).' })
    $lines += $(if ($win10.Count) { "ISO Windows có menu cài tự động: " + (($win10 | ForEach-Object { $_.Ten }) -join ', ') } else { 'Chưa có ISO Windows nào trên USB (thẻ 2. ISO): vẫn tạo được, thêm ISO rồi bấm Tạo USB lại.' })
    if ($isos.Count -gt $win10.Count) { $lines += "ISO khác (khởi động bằng Ventoy): $($isos.Count - $win10.Count)" }
    $acc = if ((Get-ComboTag $ui.cboTaiKhoan) -eq 'tu-dong') {
        "tự tạo '{0}', {1}" -f $ui.txtTen.Text.Trim(), $(if ($ui.pwdMatKhau.Password) { 'có mật khẩu' } else { 'KHÔNG mật khẩu' })
    } else { 'hỏi khi cài' }
    $lines += "Tài khoản: $acc.  Key: $($ui.cboBanQuyen.Text)."
    $after = @()
    if ($ui.cbUngDung.IsChecked) { $after += ('{0} ứng dụng' -f @($ui.lbUngDung.Items | Where-Object { $_.IsChecked }).Count) }
    if ($ui.cbOffice.IsChecked) { $after += 'Office' }
    if ($ui.cbDriver.IsChecked) { $after += 'driver' }
    if ($ui.cbCapNhat.IsChecked) { $after += 'Windows Update' }
    $lines += 'Sau khi cài: ' + $(if ($after.Count) { $after -join ', ' } else { 'không làm gì thêm' }) + '.'
    $lines += "Menu khi khởi động: hết $($ui.txtChoGiay.Text.Trim()) giây thì chọn '$($ui.cboMacDinh.Text)'."
    $ui.txtTomTat.Text = $lines -join "`n"
}

function Start-Create {
    if (-not $script:Root) { return }
    if (-not (Save-ConfigForm)) { $ui.tabs.SelectedItem = $ui.tabCauHinh; return }
    $a = @('-O', $script:Root, '-KhongDung')
    $temp = @()
    if ((Get-ComboTag $ui.cboTaiKhoan) -eq 'tu-dong') {
        $pw = $ui.pwdMatKhau.Password
        if ($pw) {
            $f = Join-Path ([IO.Path]::GetTempPath()) ('AutoSetup-mk-{0}.txt' -f [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($f, $pw, (New-Object Text.UTF8Encoding $false))
            $a += @('-MatKhauFile', $f); $temp += $f
        } else {
            if ((Show-Message "Tài khoản tự tạo sẽ KHÔNG có mật khẩu. Tiếp tục?" 'Question' 'YesNo' 'No') -ne 'Yes') { return }
            $a += '-KhongMatKhau'
        }
    }
    if ($ui.cbChayThu.IsChecked) { $a += '-ChayThu' }
    Start-Background -Title $(if ($ui.cbChayThu.IsChecked) { 'Chạy thử tạo USB' } else { 'Tạo USB' }) -Script (Join-Path $PSScriptRoot 'TaoUSB.ps1') -Arguments $a -TempFiles $temp -OnDone {
        param($code)
        Update-IsoList
        if ($code -eq 0 -and -not $ui.cbChayThu.IsChecked) { Show-Message "Đã tạo xong USB $($script:Root)." | Out-Null }
    }
}

# ---------------------------------------------------------------- gắn sự kiện, mở
Add-ComboItems $ui.cboBanQuyen $script:BanQuyen
$editions = [ordered]@{}; foreach ($k in $script:GenericKeys.Keys) { $editions[$k] = $script:GenericKeys[$k].Ten }
Add-ComboItems $ui.cboPhienBan $editions
Add-ComboItems $ui.cboTaiKhoan $script:TaiKhoan
foreach ($t in $script:MacDinh) { [void]$ui.cboMacDinh.Items.Add($t) }

$ui.txtQuyen.Text = $(if ($script:IsAdmin) { 'Quyền quản trị: có' } else { 'Không có quyền quản trị: không cài được Ventoy' })
$ui.btnLamMoiUsb.Add_Click({ [void](Update-UsbList); Select-Usb })
$ui.lvUsb.Add_SelectionChanged({ Select-Usb })
$ui.btnCaiVentoy.Add_Click({ Start-Ventoy 'I' })
$ui.btnCapNhatVentoy.Add_Click({ Start-Ventoy 'U' })
$ui.btnChonThuMuc.Add_Click({ Select-Folder })
$ui.btnThemIso.Add_Click({ Add-Iso })
$ui.btnLamMoiIso.Add_Click({ Update-IsoList })
$ui.btnMoUsb.Add_Click({ if ($script:Root) { Start-Process explorer.exe -ArgumentList "`"$($script:Root)`"" } })
$ui.btnLuuCauHinh.Add_Click({ [void](Save-ConfigForm) })
$ui.btnMoCauHinh.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($script:CfgDir)`"" })
$ui.btnTao.Add_Click({ Start-Create })
foreach ($c in 'cboTaiKhoan', 'cboBanQuyen') { $ui[$c].Add_SelectionChanged({ Update-FormState }) }
foreach ($c in 'rbTenNgauNhien', 'rbTenHoi', 'rbTenCoDinh') { $ui[$c].Add_Checked({ Update-FormState }) }
$ui.tabs.Add_SelectionChanged({
        param($s, $e)
        if ($e.OriginalSource -eq $ui.tabs -and $ui.tabs.SelectedItem -eq $ui.tabTao) { Update-Summary }
    })
$win.Add_Closing({
        param($s, $e)
        if ($script:Job) {
            Show-Message "Đang $($script:Job.Title.ToLower()), đợi xong rồi hãy đóng." 'Warning' | Out-Null
            $e.Cancel = $true
        }
    })

Import-ConfigForm
[void](Update-UsbList)
if ($O) {
    $script:DiskNo = $null
    Set-Target $O "Đích: $O  (chọn tay, không kiểm Ventoy)"
} else { Select-Usb }
Update-Buttons
$ui.tabs.SelectedIndex = [Math]::Min(3, [Math]::Max(0, $The))
if ($The -eq 3) { Update-Summary }
Add-Log ('AutoSetup_Win: giao diện tạo USB. Repo: {0}' -f $repo)
if ($ChiNap) { return }

if ($AnhRa) {
    # Dựng cửa sổ ngoài màn hình, chụp nội dung thành PNG rồi thoát.
    $win.WindowStartupLocation = 'Manual'; $win.Left = -20000; $win.Top = 0; $win.ShowActivated = $false
    $win.Show()
    $win.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $root = $win.Content
    $m = $root.Margin
    $w = [int]($root.ActualWidth + $m.Left + $m.Right); $h = [int]($root.ActualHeight + $m.Top + $m.Bottom)
    $dv = New-Object Windows.Media.DrawingVisual
    $ctx = $dv.RenderOpen()
    $ctx.DrawRectangle($win.Background, $null, (New-Object Windows.Rect 0, 0, $w, $h))
    $ctx.DrawRectangle((New-Object Windows.Media.VisualBrush $root), $null, (New-Object Windows.Rect $m.Left, $m.Top, $root.ActualWidth, $root.ActualHeight))
    $ctx.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($AnhRa)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
    $win.Close()
    exit 0
}

[void]$win.ShowDialog()
