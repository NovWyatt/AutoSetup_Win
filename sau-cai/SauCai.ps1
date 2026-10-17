<#
  AutoSetup_Win - bước sau cài Windows. Tự chạy ở lần đăng nhập đầu (FirstLogon.ps1 tạo tác vụ \AutoSetup\AutoSetup-TiepTuc),
  chạy tiếp sau mỗi lần khởi động lại cho tới khi xong; chạy lại bằng tay bằng CHAY_LAI.bat.

  Các bước (theo thứ tự; bước đã xong không chạy lại, trừ khi -LamLai hoặc -Chi):
    o-du-lieu         đưa phân vùng dữ liệu về chữ D (USB hay chiếm D lúc cài)            sauCai.oDuLieuLaD
    winget            bảo đảm winget chạy được (đăng ký App Installer, cập nhật nguồn)     cần mạng
    ung-dung          cài ứng dụng macDinh = true trong cau-hinh\UngDung.json              sauCai.ungDung, cần mạng
    office            cài Office từ USB (\AutoSetup\office: setup.exe + .xml)              sauCai.office
    driver            nạp driver trên USB (\AutoSetup\drivers) và driver từ Windows Update  sauCai.driver
    cap-nhat-windows  cài bản cập nhật Windows                                             sauCai.capNhatWindows, cần mạng
    ten-may           đổi tên máy theo tên nhập lúc khởi động USB (tenMay = hoi)
    bao-cao           ghi báo cáo vào C:\AutoSetup\ket_qua (và \AutoSetup\ket_qua trên USB)
  Cấu hình đọc từ ..\cau-hinh (C:\AutoSetup\cau-hinh, hoặc thư mục cau-hinh trên USB khi chạy thẳng từ USB).
  Trạng thái: C:\AutoSetup\TrangThai.json. Nhật ký: C:\AutoSetup\ket_qua\NhatKy_SauCai_<máy>.log.

  Tham số: -Chi <bước,...> chỉ chạy các bước này (kể cả đã xong); -LamLai làm lại mọi bước; -ChayThu chỉ in việc
  sẽ làm, không đổi máy; -TuDong (tác vụ tự chạy gọi); -KhongDung không chờ Enter khi xong.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (không có quyền Admin), 3 làm được một phần, 4 chờ khởi động lại.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]]$Chi = @(),
    [switch]$LamLai,
    [switch]$ChayThu,
    [switch]$TuDong,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # thanh tiến trình của Invoke-WebRequest, Add-AppxPackage che mất chữ đã in
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.0'
$here = $PSScriptRoot
. (Join-Path $here 'lib\Json.ps1')
. (Join-Path $here 'lib\Chung.ps1')
. (Join-Path $here 'lib\UngDung.ps1')
. (Join-Path $here 'lib\Driver.ps1')
. (Join-Path $here 'lib\HeThong.ps1')

$script:Goc = if ($env:AUTOSETUP_GOC) { $env:AUTOSETUP_GOC } else { 'C:\AutoSetup' }
$script:StateFile = Join-Path $script:Goc 'TrangThai.json'
$script:ResultDir = Join-Path $script:Goc 'ket_qua'
$script:ConfigDir = Join-Path (Split-Path -Parent $here) 'cau-hinh'
$script:TaskName = 'AutoSetup-TiepTuc'
$script:MaxReboots = 4   # FirstLogon.ps1 đặt số lần tự đăng nhập bằng con số này: đổi một chỗ thì đổi cả chỗ kia
$script:Steps = @(
    [pscustomobject]@{ Id = 'o-du-lieu'; Ten = 'Ổ dữ liệu là D'; CanMang = $false }
    [pscustomobject]@{ Id = 'winget'; Ten = 'Chuẩn bị winget'; CanMang = $true }
    [pscustomobject]@{ Id = 'ung-dung'; Ten = 'Cài ứng dụng'; CanMang = $true }
    [pscustomobject]@{ Id = 'office'; Ten = 'Cài Office từ USB'; CanMang = $false }
    [pscustomobject]@{ Id = 'driver'; Ten = 'Driver'; CanMang = $false }
    [pscustomobject]@{ Id = 'cap-nhat-windows'; Ten = 'Cập nhật Windows'; CanMang = $true }
    [pscustomobject]@{ Id = 'ten-may'; Ten = 'Đổi tên máy'; CanMang = $false }
    [pscustomobject]@{ Id = 'bao-cao'; Ten = 'Báo cáo'; CanMang = $false }
)
$script:StatusText = @{ 'xong' = 'xong'; 'loi' = 'lỗi'; 'bo-qua' = 'bỏ qua'; 'cho-mang' = 'chờ mạng'; 'cho-khoi-dong-lai' = 'chờ khởi động lại'; 'chay-thu' = 'chạy thử' }

# ---------------------------------------------------------------- trạng thái, cấu hình
function New-State {
    return [pscustomobject]@{ phienBan = $script:Version; batDau = (Get-Date).ToString('s'); lanChay = 0; khoiDongLai = 0; doiTenMay = $false; buoc = [pscustomobject]@{}; ungDung = @(); driver = [pscustomobject]@{ vong = 0; usbXong = $false; daCai = @(); loi = @() } }
}

function Read-State {
    if ($LamLai -or -not (Test-Path -LiteralPath $script:StateFile)) { return (New-State) }
    try { return (Read-JsonFile $script:StateFile) } catch { Write-Warn "Trạng thái hỏng, làm lại từ đầu: $($_.Exception.Message)"; return (New-State) }
}

function Save-State {
    param($State)
    if ($ChayThu) { return }
    Write-JsonFile $script:StateFile $State
}

function Set-StepResult {
    param($State, [string]$Id, [string]$Status, [string]$Note = '')
    $v = [pscustomobject]@{ trangThai = $Status; luc = (Get-Date).ToString('s'); ghiChu = $Note }
    if ($State.buoc.PSObject.Properties[$Id]) { $State.buoc.$Id = $v } else { $State.buoc | Add-Member -NotePropertyName $Id -NotePropertyValue $v }
}

function Get-StepStatus {
    param($State, [string]$Id)
    $p = $State.buoc.PSObject.Properties[$Id]
    if ($p) { return [string]$p.Value.trangThai }
    return ''
}

function Get-Cfg {
    # Giá trị cấu hình theo đường dẫn 'a.b'; không có thì $Default.
    param([string]$Path, $Default = $null)
    $cur = $script:Config
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $Default }
        $p = $cur.PSObject.Properties[$part]
        if (-not $p) { return $Default }
        $cur = $p.Value
    }
    if ($null -eq $cur) { return $Default }
    return $cur
}

function Read-KhoiDong {
    # C:\AutoSetup\KhoiDong.json do FirstLogon.ps1 ghi (tên máy nhập lúc khởi động USB...).
    $f = Join-Path $script:Goc 'KhoiDong.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Read-JsonFile $f) } catch { return $null }
}

# ---------------------------------------------------------------- khởi động lại, tác vụ tự chạy
function Register-ResumeTask {
    # Tác vụ chạy lại SauCai.ps1 khi tài khoản này đăng nhập (sau khi khởi động lại).
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $script = Join-Path $script:Goc 'sau-cai\SauCai.ps1'
    if (-not (Test-Path -LiteralPath $script)) { $script = $PSCommandPath }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -TuDong' -f $script)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $script:TaskName -TaskPath '\AutoSetup\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Unregister-ResumeTask {
    try { Unregister-ScheduledTask -TaskName $script:TaskName -TaskPath '\AutoSetup\' -Confirm:$false -ErrorAction Stop } catch { }
}

function Request-Reboot {
    # Lưu trạng thái, bảo đảm tác vụ tự chạy còn đó, rồi khởi động lại (hoặc nhắc người dùng). Trả mã thoát 4.
    param($State, [string]$Why)
    $State.khoiDongLai = [int]$State.khoiDongLai + 1
    Save-State $State
    Write-Line ''
    Write-Warn "Cần khởi động lại: $Why"
    if ($ChayThu) { return 4 }
    try { Register-ResumeTask } catch { Write-Warn "Không tạo được tác vụ tự chạy tiếp: $($_.Exception.Message). Sau khi khởi động lại, chạy CHAY_LAI.bat." }
    if ((Get-Cfg 'sauCai.tuKhoiDongLai' $true) -eq $true) {
        Write-Info 'Máy tự khởi động lại sau 60 giây, đăng nhập lại để chạy tiếp (gõ shutdown /a trong cửa sổ khác để huỷ).'
        & shutdown.exe /r /t 60 /c 'AutoSetup: khoi dong lai de cai tiep. Dang nhap lai de chay tiep.' | Out-Null
    } else {
        Write-Info 'Hãy khởi động lại máy rồi đăng nhập: bước sau cài sẽ tự chạy tiếp.'
    }
    return 4
}

# ---------------------------------------------------------------- các bước
function Invoke-StepODuLieu {
    if ((Get-Cfg 'sauCai.oDuLieuLaD' $true) -ne $true) { return @('bo-qua', 'Tắt trong cấu hình (sauCai.oDuLieuLaD).') }
    $r = Set-DataDriveLetter -DryRun:$ChayThu
    return @($r.TrangThai, $r.GhiChu)
}

function Invoke-StepWinget {
    if ((Get-Cfg 'sauCai.ungDung' $true) -ne $true) { return @('bo-qua', 'Không cài ứng dụng (sauCai.ungDung = false).') }
    $r = Initialize-Winget
    if ($r.Ok) { return @('xong', $r.GhiChu) }
    return @('loi', $r.GhiChu)
}

function Invoke-StepUngDung {
    param($State)
    if ((Get-Cfg 'sauCai.ungDung' $true) -ne $true) { return @('bo-qua', 'Tắt trong cấu hình (sauCai.ungDung).') }
    if (-not (Get-WingetPath)) { return @('loi', 'winget chưa chạy được (xem bước winget).') }
    $apps = Read-AppList (Join-Path $script:ConfigDir 'UngDung.json')
    $sel = Select-Apps $apps
    foreach ($s in $sel.BoQua) { Write-Info "Bỏ qua $($s.App.ten): $($s.LyDo)." }
    if (-not $sel.Chon.Count) { return @('bo-qua', 'Không có ứng dụng nào macDinh = true.') }
    Write-Info ('Sẽ cài: ' + (($sel.Chon | ForEach-Object { $_.ten }) -join ', '))
    $root = [string](Get-Cfg 'sauCai.thuMucCai' '')
    if ($root -and -not (Test-Path -LiteralPath ($root.Substring(0, 3)))) { Write-Warn "Không có ổ của thư mục cài $root, cài vào chỗ mặc định."; $root = '' }
    $res = Install-Apps -Apps $sel.Chon -InstallRoot $root -TimeoutSeconds (60 * [int](Get-Cfg 'sauCai.choCaiPhut' 30)) -DryRun:$ChayThu
    if (-not $ChayThu) { $State.ungDung = $res }
    $bad = @($res | Where-Object { $_.ketQua -eq 'loi' })
    if ($ChayThu) { return @('chay-thu', '') }
    if ($bad.Count) { return @('loi', ('Chưa cài được: ' + (($bad | ForEach-Object { $_.ten }) -join ', '))) }
    return @('xong', ('{0} ứng dụng.' -f $res.Count))
}

function Invoke-StepOffice {
    param([bool]$Net)
    if ((Get-Cfg 'sauCai.office' $true) -ne $true) { return @('bo-qua', 'Tắt trong cấu hình (sauCai.office).') }
    $r = Install-OfficeFromUsb -UsbRoot (Find-UsbRoot) -HasInternet $Net -DryRun:$ChayThu
    return @($r.TrangThai, $r.GhiChu)
}

function Invoke-StepDriver {
    param($State, [bool]$Net)
    if ((Get-Cfg 'sauCai.driver' $true) -ne $true) { return @('bo-qua', 'Tắt trong cấu hình (sauCai.driver).') }
    $notes = @(); $reboot = $false; $failed = $false
    $usb = Find-UsbRoot
    if ($usb -and $State.driver.usbXong -ne $true) {
        $folder = Join-Path $usb 'AutoSetup\drivers'
        if (Test-Path -LiteralPath $folder) {
            $u = Install-UsbDrivers -Folder $folder -DryRun:$ChayThu
            $notes += "USB: $($u.GhiChu)"
            if ($u.TrangThai -eq 'loi') { $failed = $true }
            if ($u.KhoiDongLai) { $reboot = $true }
        }
        if (-not $ChayThu) { $State.driver.usbXong = $true }
    }
    if ($Net) {
        $w = Invoke-WindowsUpdate -Kind Driver -DryRun:$ChayThu
        $notes += "Windows Update: $($w.GhiChu)"
        if (-not $ChayThu) {
            $truoc = @($State.driver.daCai).Count
            $State.driver.vong = [int]$State.driver.vong + 1
            $State.driver.daCai = @($State.driver.daCai) + @($w.DaCai)
            $State.driver.loi = @($w.Loi)
            # Vòng sau khởi động lại chỉ thấy "không còn gì": giữ cho báo cáo biết các vòng trước đã cài bao nhiêu.
            if ($truoc) { $notes[-1] += " Tổng đã cài qua $($State.driver.vong) vòng: $(@($State.driver.daCai).Count) mục." }
        }
        if ($w.TrangThai -eq 'loi') { $failed = $true }
        # Cài xong có driver mới cần khởi động lại: chạy thêm một vòng sau khi khởi động (tối đa 3 vòng).
        if ($w.KhoiDongLai -or ($w.DaCai.Count -and [int]$State.driver.vong -lt 3)) { $reboot = $true }
    } else { $notes += 'Windows Update: bỏ qua vì chưa có mạng.' }
    if ($ChayThu) { return @('chay-thu', ($notes -join '; ')) }
    if ($reboot -and [int]$State.driver.vong -lt 3) { return @('cho-khoi-dong-lai', ($notes -join '; ')) }
    if ($failed) { return @('loi', ($notes -join '; ')) }
    if (-not $Net) { return @('cho-mang', ($notes -join '; ')) }
    return @('xong', ($notes -join '; '))
}

function Invoke-StepCapNhatWindows {
    if ((Get-Cfg 'sauCai.capNhatWindows' $false) -ne $true) { return @('bo-qua', 'Tắt trong cấu hình (sauCai.capNhatWindows).') }
    $w = Invoke-WindowsUpdate -Kind Software -DryRun:$ChayThu
    if ($ChayThu) { return @('chay-thu', $w.GhiChu) }
    if ($w.KhoiDongLai) { return @('cho-khoi-dong-lai', $w.GhiChu) }
    return @($w.TrangThai, $w.GhiChu)
}

function Invoke-StepTenMay {
    param($State)
    $kd = Read-KhoiDong
    $name = if ($kd -and $kd.PSObject.Properties['tenMayNhap']) { ([string]$kd.tenMayNhap).Trim() } else { '' }
    if (-not $name -or $name -like '*$$*') { return @('bo-qua', 'Không có tên máy nhập lúc khởi động USB.') }
    if ($name -notmatch '^[A-Za-z0-9-]{1,15}$' -or $name -match '^\d+$' -or $name -match '^-|-$') {
        return @('loi', "Tên máy '$name' không hợp lệ (1-15 ký tự chữ, số, dấu gạch ngang). Đổi trong Cài đặt > Hệ thống > Giới thiệu.")
    }
    if ($name -eq $env:COMPUTERNAME) { return @('xong', "Tên máy đã là $name.") }
    Write-Plan "Đổi tên máy $env:COMPUTERNAME thành $name (có hiệu lực sau khi khởi động lại)"
    if ($ChayThu) { return @('chay-thu', '') }
    try { Rename-Computer -NewName $name -Force -ErrorAction Stop; $State.doiTenMay = $true; return @('xong', "Đổi tên máy thành $name.") }
    catch { return @('loi', "Đổi tên máy lỗi: $($_.Exception.Message.Trim())") }
}

function Invoke-StepBaoCao {
    param($State)
    $info = Get-MachineInfo
    $problems = Get-ProblemDevices
    $start = Get-Date
    $stamp = '{0}_{1:yyyyMMdd_HHmmss}' -f $env:COMPUTERNAME, $start
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("BÁO CÁO AUTOSETUP - $($start.ToString('dd/MM/yyyy HH:mm'))")
    $lines.Add(('=' * 70))
    $lines.Add("Máy:        $($info.tenMay)  ($($info.hang) $($info.model), serial $($info.serial))")
    $lines.Add("Windows:    $($info.windows)")
    $lines.Add("Bản quyền:  $($info.banQuyen)")
    $lines.Add("RAM:        $($info.ramGB) GB")
    $lines.Add('')
    $lines.Add('CÁC BƯỚC')
    foreach ($s in $script:Steps | Where-Object { $_.Id -ne 'bao-cao' }) {
        $p = $State.buoc.PSObject.Properties[$s.Id]
        $st = if ($p) { $script:StatusText[[string]$p.Value.trangThai] } else { 'chưa chạy' }
        $note = if ($p -and $p.Value.ghiChu) { " - $($p.Value.ghiChu)" } else { '' }
        $lines.Add(('  {0,-22} {1}{2}' -f $s.Ten, $st, $note))
    }
    if (@($State.ungDung).Count) {
        $lines.Add('')
        $lines.Add('ỨNG DỤNG')
        $txt = @{ 'da-co' = 'đã có sẵn'; 'da-cai' = 'đã cài'; 'loi' = 'LỖI'; 'chay-thu' = 'chạy thử' }
        foreach ($a in $State.ungDung) { $lines.Add(('  {0,-40} {1}{2}' -f $a.ten, $txt[[string]$a.ketQua], $(if ($a.ghiChu) { " ($($a.ghiChu))" } else { '' }))) }
    }
    $lines.Add('')
    $lines.Add('Ổ ĐĨA')
    foreach ($v in $info.oDia) { $lines.Add(('  {0,-4} {1,-16} {2,-10} {3,8} GB, còn trống {4} GB' -f $v.o, $v.nhan, $v.loai, $v.dungLuongGB, $v.conTrongGB)) }
    if (@($info.bitLocker).Count) {
        $lines.Add('')
        $lines.Add('BITLOCKER')
        foreach ($b in $info.bitLocker) { $lines.Add(('  {0,-4} bảo vệ: {1}, mã hoá: {2}' -f $b.o, $b.baoVe, $b.maHoa)) }
    }
    $lines.Add('')
    if ($problems.Count) {
        $lines.Add("THIẾT BỊ CHƯA CÓ DRIVER HOẶC BÁO LỖI ($($problems.Count))")
        foreach ($d in $problems) { $lines.Add(('  {0} [{1}] {2}' -f $d.ten, $d.lop, $d.ma)) }
    } else { $lines.Add('Thiết bị: không có thiết bị nào thiếu driver hay báo lỗi.') }
    $lines.Add('')
    $lines.Add('Chạy lại một bước: C:\AutoSetup\sau-cai\CHAY_LAI.bat (chuột phải > Run as administrator).')

    if ($ChayThu) { foreach ($l in $lines) { Write-Sub $l }; return @('chay-thu', '') }
    New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null
    $txtFile = Join-Path $script:ResultDir "BaoCao_$stamp.txt"
    [IO.File]::WriteAllLines($txtFile, $lines, (New-Object Text.UTF8Encoding $true))
    Write-JsonFile (Join-Path $script:ResultDir "BaoCao_$stamp.json") ([ordered]@{ may = $info; trangThai = $State; thietBiLoi = $problems })
    $usb = Find-UsbRoot
    if ($usb) {
        try {
            $dst = Join-Path $usb 'AutoSetup\ket_qua'
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item -LiteralPath $txtFile -Destination $dst -Force
        } catch { Write-Warn "Không chép được báo cáo lên USB: $($_.Exception.Message)" }
    }
    $script:ReportFile = $txtFile
    return @('xong', $txtFile)
}

function Invoke-Step {
    param($Step, $State, [bool]$Net)
    switch ($Step.Id) {
        'o-du-lieu' { return Invoke-StepODuLieu }
        'winget' { return Invoke-StepWinget }
        'ung-dung' { return Invoke-StepUngDung $State }
        'office' { return Invoke-StepOffice $Net }
        'driver' { return Invoke-StepDriver $State $Net }
        'cap-nhat-windows' { return Invoke-StepCapNhatWindows }
        'ten-may' { return Invoke-StepTenMay $State }
        'bao-cao' { return Invoke-StepBaoCao $State }
    }
}

function Clear-AutoLogon {
    # Tắt tự đăng nhập và xoá mật khẩu Windows lưu cho nó. Setup cất mật khẩu trong bí mật LSA "DefaultPassword", Windows
    # còn giữ một bản "CachedDefaultPassword": chỉ đặt AutoAdminLogon = 0 thì cả hai vẫn nằm trên máy giao khách (thử
    # máy ảo 12/10 và 17/10/2026 thấy còn).
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    try {
        Set-ItemProperty -LiteralPath $k -Name 'AutoAdminLogon' -Value '0' -ErrorAction Stop
        Remove-ItemProperty -LiteralPath $k -Name 'DefaultPassword', 'AutoLogonCount' -ErrorAction SilentlyContinue
    } catch { }
    foreach ($name in 'DefaultPassword', 'CachedDefaultPassword') {
        $code = try { Remove-LsaSecret $name } catch { -1 }
        if ($code -notin 0, 2) { Write-Warn "Không xoá được mật khẩu tự đăng nhập Windows cất trong LSA ($name, mã $code)." }
    }
}

function Start-KeepAwake {
    # Giữ máy không ngủ, màn hình không tắt trong lúc chạy để người cài xem được tiến độ (chỉ trong tiến trình này,
    # không đổi cài đặt nguồn).
    try {
        Add-Type -Namespace AutoSetup -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);' -ErrorAction Stop
        [void][AutoSetup.Power]::SetThreadExecutionState([uint32]'0x80000003')   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
    } catch { }
}

# ---------------------------------------------------------------- chạy
function Invoke-Main {
    $unknown = @($Chi | ForEach-Object { $_ -split ',' } | Where-Object { $_ -and $_ -notin $script:Steps.Id })
    if ($unknown.Count) { Write-Bad ("Không có bước: {0}. Các bước: {1}." -f ($unknown -join ', '), ($script:Steps.Id -join ', ')); return 1 }
    $only = @($Chi | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    if (-not $ChayThu -and -not (Test-IsAdmin)) { Write-Bad 'Cần chạy bằng quyền Admin (chuột phải CHAY_LAI.bat > Run as administrator).'; return 2 }

    $script:Config = Read-JsonFile (Join-Path $script:ConfigDir 'CauHinh.json')
    $state = Read-State
    $state.lanChay = [int]$state.lanChay + 1
    Write-Head ("AUTOSETUP - BƯỚC SAU CÀI WINDOWS{0}" -f $(if ($ChayThu) { ' (CHẠY THỬ)' }))
    Write-Info "Máy $env:COMPUTERNAME, tài khoản $env:USERNAME, lần chạy $($state.lanChay)."

    # Bước nào còn phải chạy, có cần mạng không.
    $todo = @()
    foreach ($s in $script:Steps) {
        if ($only.Count) { if ($s.Id -in $only) { $todo += $s }; continue }
        $st = Get-StepStatus $state $s.Id
        if ($s.Id -eq 'bao-cao' -or $st -notin 'xong', 'bo-qua', 'loi') { $todo += $s }
    }
    $net = $false
    if (@($todo | Where-Object { $_.CanMang -or $_.Id -in 'office', 'driver' }).Count) {
        $wait = if ([int]$state.lanChay -le 1) { [int](Get-Cfg 'sauCai.choMangPhut' 10) } else { 2 }
        $net = Wait-Internet -Minutes $wait
    }

    $i = 0
    foreach ($s in $todo) {
        $i++
        try { $Host.UI.RawUI.WindowTitle = "AutoSetup - $i/$($todo.Count) $($s.Ten)" } catch { }
        Write-Head "$i/$($todo.Count) $($s.Ten)"
        if ($s.CanMang -and -not $net) {
            $why = 'Chưa có Internet.'
            $off = ($s.Id -eq 'cap-nhat-windows' -and (Get-Cfg 'sauCai.capNhatWindows' $false) -ne $true) -or
                ($s.Id -in 'winget', 'ung-dung' -and (Get-Cfg 'sauCai.ungDung' $true) -ne $true)
            if ($off) {
                Write-Warn "$($s.Ten): bỏ qua - Tắt trong cấu hình."
                Set-StepResult $state $s.Id 'bo-qua' 'Tắt trong cấu hình.'
                Save-State $state
                continue
            }
            Write-Warn $why
            Set-StepResult $state $s.Id 'cho-mang' $why
            Save-State $state
            continue
        }
        try { $r = @(Invoke-Step $s $state $net) }
        catch { $r = @('loi', "Lỗi: $($_.Exception.Message.Trim())") }
        $status = [string]$r[0]; $note = if ($r.Count -gt 1) { [string]$r[1] } else { '' }
        Set-StepResult $state $s.Id $status $note
        Save-State $state
        $msg = '{0}: {1}{2}' -f $s.Ten, $script:StatusText[$status], $(if ($note) { " - $note" } else { '' })
        switch ($status) { 'xong' { Write-Ok $msg } 'loi' { Write-Bad $msg } 'chay-thu' { Write-Info $msg } default { Write-Warn $msg } }
        if ($status -eq 'cho-khoi-dong-lai') {
            if ([int]$state.khoiDongLai -ge $script:MaxReboots) {
                Set-StepResult $state $s.Id 'loi' "Đã khởi động lại $($state.khoiDongLai) lần mà vẫn cần khởi động lại; dừng để không lặp mãi. $note"
                Save-State $state
                continue
            }
            return (Request-Reboot $state "$($s.Ten): $note")
        }
    }

    # Xong lượt: dọn dẹp, tổng kết.
    $pending = @($script:Steps | Where-Object { (Get-StepStatus $state $_.Id) -in 'cho-mang', 'cho-khoi-dong-lai', '' -and $_.Id -ne 'bao-cao' })
    $failed = @($script:Steps | Where-Object { (Get-StepStatus $state $_.Id) -eq 'loi' })
    if (-not $ChayThu) {
        if (-not $pending.Count) { Unregister-ResumeTask }
        # Còn khởi động lại để đổi tên máy (ngay dưới): giữ tự đăng nhập cho lần đó, lượt chạy sau mới dọn.
        if ($state.doiTenMay -ne $true) { Clear-AutoLogon }
    }
    Write-Head 'TỔNG KẾT'
    foreach ($s in $script:Steps) {
        $st = Get-StepStatus $state $s.Id
        if (-not $st) { continue }
        Write-Line ('{0,-22} {1}' -f $s.Ten, $script:StatusText[$st])
    }
    if ($script:ReportFile) { Write-Info "Báo cáo: $script:ReportFile" }
    if ($pending.Count) { Write-Warn ('Còn chờ: ' + (($pending | ForEach-Object { $_.Ten }) -join ', ') + '. Có mạng rồi thì chạy CHAY_LAI.bat.') }
    if ($state.doiTenMay -eq $true -and -not $ChayThu) {
        $state.doiTenMay = $false
        Save-State $state
        return (Request-Reboot $state 'đổi tên máy')
    }
    if ($ChayThu) { return 0 }
    if ($failed.Count) { return 3 }
    if ($pending.Count) { return 3 }
    return 0
}

if ($env:AUTOSETUP_TEST_NAP) { return }   # bài thử nạp các hàm rồi tự gọi
$transcript = $false
if (-not $ChayThu) {
    try {
        New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null
        Start-Transcript -Path (Join-Path $script:ResultDir "NhatKy_SauCai_$env:COMPUTERNAME.log") -Append | Out-Null
        $transcript = $true
    } catch { }
}
Set-ConsoleFont
Start-KeepAwake
$code = 1
try { $code = Invoke-Main }
catch { Write-Bad "Lỗi không lường trước: $($_.Exception.Message)"; Write-Sub $_.ScriptStackTrace; $code = 1 }
if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
if ($script:ReportFile -and $TuDong -and $code -ne 4) { try { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ReportFile) } catch { } }
if (-not $KhongDung -and -not [Console]::IsInputRedirected -and $code -ne 4) {
    Write-Host ''
    [void](Read-Host '  Xong. Bấm Enter để đóng cửa sổ')
}
exit $code
