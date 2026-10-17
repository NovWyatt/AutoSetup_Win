<#
  AutoSetup_Win - chạy một lần ở lần đăng nhập đầu tiên (FirstLogonCommands, quyền Admin của tài khoản đó).
    1. Xoá file trả lời Setup còn trong C:\Windows\Panther (có thể có mật khẩu tài khoản, dù chỉ mã hoá base64).
    2. Bản có bước sau cài: tìm USB AutoSetup (thư mục \AutoSetup\sau-cai ở gốc ổ), chép sau-cai và cau-hinh vào
       C:\AutoSetup, tạo tác vụ "AutoSetup-TiepTuc" chạy SauCai.ps1 ở mỗi lần đăng nhập (để chạy tiếp sau khi khởi
       động lại) rồi chạy nó ngay. Không thấy USB thì để lại hướng dẫn trên Desktop.
    3. Tự đăng nhập (tài khoản tự tạo): có bước sau cài thì đặt số lần tự đăng nhập cho các lần nó khởi động lại
       (SauCai tắt khi xong lượt); không có thì tắt ngay, xoá mật khẩu Setup cất trong LSA.
  Script này không chờ bước sau cài chạy xong: Windows chỉ vào Desktop khi FirstLogonCommands kết thúc.
#>
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'FirstLogon.log'
$goc = 'C:\AutoSetup'
$taskName = 'AutoSetup-TiepTuc'

function Write-Log {
    param([string]$Text)
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $Text
    [IO.File]::AppendAllText($logFile, $line + "`r`n", (New-Object Text.UTF8Encoding $true))
}

function Find-UsbRoot {
    # Gốc ổ có \AutoSetup\sau-cai\SauCai.ps1 (bỏ qua ổ Windows). Trả $null khi không có.
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $r = $d.Root
        if (-not $r -or $r -like "$env:SystemDrive*") { continue }
        if (Test-Path -LiteralPath (Join-Path $r 'AutoSetup\sau-cai\SauCai.ps1')) { return $r.TrimEnd('\') }
    }
    return $null
}

$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

function Test-AutoLogon {
    # Unattend bật tự đăng nhập (tài khoản tự tạo, taiKhoan.tuDangNhap) thì Winlogon có AutoAdminLogon = 1.
    return ([string](Get-ItemProperty -LiteralPath $winlogon -ErrorAction SilentlyContinue).AutoAdminLogon -eq '1')
}

function Remove-LsaSecret {
    # Bản sao của hàm cùng tên trong sau-cai\lib\HeThong.ps1 (script này chạy một mình). Trả mã lỗi Win32: 0 đã xoá,
    # 2 vốn không có.
    param([Parameter(Mandatory)] [string]$Name)
    if (-not ('AutoSetup.Lsa' -as [type])) {
        Add-Type -Namespace AutoSetup -Name Lsa -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct ObjectAttributes { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct UnicodeString { public ushort Length; public ushort MaximumLength; [MarshalAs(UnmanagedType.LPWStr)] public string Buffer; }
[DllImport("advapi32.dll")] public static extern uint LsaOpenPolicy(IntPtr systemName, ref ObjectAttributes attributes, uint access, out IntPtr policy);
[DllImport("advapi32.dll")] public static extern uint LsaStorePrivateData(IntPtr policy, ref UnicodeString keyName, IntPtr privateData);
[DllImport("advapi32.dll")] public static extern uint LsaClose(IntPtr policy);
[DllImport("advapi32.dll")] public static extern int LsaNtStatusToWinError(uint status);
'@
    }
    $attr = New-Object AutoSetup.Lsa+ObjectAttributes
    $attr.Length = [Runtime.InteropServices.Marshal]::SizeOf($attr)
    $policy = [IntPtr]::Zero
    $st = [AutoSetup.Lsa]::LsaOpenPolicy([IntPtr]::Zero, [ref]$attr, 0x000F0FFF, [ref]$policy)   # POLICY_ALL_ACCESS
    if ($st -ne 0) { return [AutoSetup.Lsa]::LsaNtStatusToWinError($st) }
    try {
        $key = New-Object AutoSetup.Lsa+UnicodeString
        $key.Buffer = $Name; $key.Length = [uint16]($Name.Length * 2); $key.MaximumLength = [uint16]($Name.Length * 2 + 2)
        return [AutoSetup.Lsa]::LsaNtStatusToWinError([AutoSetup.Lsa]::LsaStorePrivateData($policy, [ref]$key, [IntPtr]::Zero))
    } finally { [void][AutoSetup.Lsa]::LsaClose($policy) }
}

function Disable-AutoLogon {
    # Không có bước sau cài cần khởi động lại: tắt tự đăng nhập ngay. Để nguyên thì Windows còn tự đăng nhập thêm một
    # lần (Windows cộng 1 vào LogonCount của unattend) và mật khẩu nằm mãi trong bí mật LSA "DefaultPassword" (cùng bản
    # "CachedDefaultPassword").
    if (-not (Test-AutoLogon)) { return }
    try {
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '0' -ErrorAction Stop
        Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword', 'AutoLogonCount' -ErrorAction SilentlyContinue
        $codes = foreach ($name in 'DefaultPassword', 'CachedDefaultPassword') { "$name $(Remove-LsaSecret $name)" }
        Write-Log "đã tắt tự đăng nhập (xoá mật khẩu trong LSA, mã: $($codes -join ', '))"
    } catch { Write-Log "LỖI tắt tự đăng nhập: $($_.Exception.Message)" }
}

function Set-AutoLogonCount {
    # Số lần Windows còn tự đăng nhập kể từ giờ (Winlogon trừ 1 mỗi lần, về 0 thì tự tắt). Ghi thẳng registry nên không
    # dính lỗi "+1" của LogonCount trong unattend.
    param([int]$Count)
    try {
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -Value $Count -Type DWord -ErrorAction Stop
        Write-Log "tự đăng nhập: còn $Count lần cho các lần khởi động lại của bước sau cài"
    } catch { Write-Log "LỖI đặt số lần tự đăng nhập: $($_.Exception.Message)" }
}

Write-Log '=== Lần đăng nhập đầu tiên ==='
$cfg = $null
try { $cfg = [IO.File]::ReadAllText((Join-Path $here 'AutoSetup.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json }
catch { Write-Log "LỖI đọc AutoSetup.json: $($_.Exception.Message)" }

foreach ($f in 'C:\Windows\Panther\unattend.xml', 'C:\Windows\Panther\unattend-original.xml', 'C:\Windows\Panther\Unattend\unattend.xml') {
    if (Test-Path -LiteralPath $f) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; Write-Log "đã xoá $f" } catch { Write-Log "LỖI xoá $f`: $($_.Exception.Message)" }
    }
}

# Tài khoản tự tạo: file unattend chỉ ghi được tên hiển thị không dấu, đặt lại tên có dấu ở đây.
if ($cfg -and $cfg.PSObject.Properties['taiKhoan'] -and $cfg.taiKhoan.tenHienThi) {
    try {
        Set-LocalUser -Name ([string]$cfg.taiKhoan.ten) -FullName ([string]$cfg.taiKhoan.tenHienThi) -ErrorAction Stop
        Write-Log "tên hiển thị của $($cfg.taiKhoan.ten): $($cfg.taiKhoan.tenHienThi)"
    } catch { Write-Log "LỖI đặt tên hiển thị: $($_.Exception.Message)" }
}

if (-not $cfg -or $cfg.sauCai -ne $true) { Write-Log 'Bản "Chỉ Windows": không chạy bước sau cài.'; Disable-AutoLogon; exit 0 }

# USB có thể được gắn chậm hơn lúc đăng nhập vài giây: đợi tối đa 90 giây.
$usb = $null
for ($i = 0; $i -lt 18 -and -not $usb; $i++) {
    $usb = Find-UsbRoot
    if (-not $usb) { Start-Sleep -Seconds 5 }
}

$tenMayNhap = ''
if ($cfg.PSObject.Properties['tenMayNhap']) { $tenMayNhap = ([string]$cfg.tenMayNhap).Trim() }
$khoiDong = [ordered]@{ bienThe = [string]$cfg.bienThe; tenMayNhap = $tenMayNhap; luc = (Get-Date).ToString('s'); nguonUSB = [string]$usb }

if (-not $usb) {
    Write-Log 'Không thấy USB AutoSetup (\AutoSetup\sau-cai\SauCai.ps1).'
    try {
        $desk = [Environment]::GetFolderPath('Desktop')
        $note = "AutoSetup: chưa chạy bước sau cài vì không thấy USB.`r`n`r`nCắm USB AutoSetup rồi chạy (chuột phải > Run as administrator):`r`n    <ổ USB>:\AutoSetup\sau-cai\CHAY_LAI.bat`r`n"
        [IO.File]::WriteAllText((Join-Path $desk 'AutoSetup - chua chay buoc sau cai.txt'), $note, (New-Object Text.UTF8Encoding $true))
    } catch { Write-Log "LỖI ghi hướng dẫn lên Desktop: $($_.Exception.Message)" }
    Disable-AutoLogon
    exit 0
}

Write-Log "USB AutoSetup: $usb"
try {
    New-Item -ItemType Directory -Path $goc -Force | Out-Null
    foreach ($sub in 'sau-cai', 'cau-hinh') {
        $dst = Join-Path $goc $sub
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction Stop }
        Copy-Item -LiteralPath (Join-Path $usb "AutoSetup\$sub") -Destination $dst -Recurse -Force -ErrorAction Stop
    }
    $json = ($khoiDong.GetEnumerator() | ForEach-Object { '    "{0}": "{1}"' -f $_.Key, ([string]$_.Value).Replace('\', '\\').Replace('"', '\"') }) -join ",`n"
    [IO.File]::WriteAllText((Join-Path $goc 'KhoiDong.json'), "{`n$json`n}`n", (New-Object Text.UTF8Encoding $false))
    Write-Log "đã chép bước sau cài vào $goc"
} catch { Write-Log "LỖI chép từ USB: $($_.Exception.Message)"; Disable-AutoLogon; exit 0 }

# Tài khoản đang đăng nhập (FirstLogonCommands chạy bằng tài khoản đó; phòng khi chạy bằng SYSTEM thì lấy người dùng của phiên).
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$user = $me.Name
if ($me.User.Value -eq 'S-1-5-18') {
    try { $user = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { }
}
Write-Log "tài khoản chạy bước sau cài: $user"

# Bước sau cài có thể khởi động lại nhiều lần (driver tối đa 3 vòng, thêm 1 lần đổi tên máy; SauCai dừng hẳn khi đã
# khởi động lại 4 lần). Mỗi lần cần tự đăng nhập thì mới chạy tiếp mà không ai phải gõ mật khẩu. SauCai tắt tự đăng
# nhập và xoá mật khẩu trong LSA khi xong lượt; nếu nó hỏng giữa chừng, mật khẩu nằm trong LSA tới khi bộ đếm về 0.
if (Test-AutoLogon) {
    Set-AutoLogonCount 4   # bằng $script:MaxReboots trong sau-cai\SauCai.ps1: đổi một chỗ thì đổi cả chỗ kia
}

try {
    $script = Join-Path $goc 'sau-cai\SauCai.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -TuDong' -f $script)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -TaskPath '\AutoSetup\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\AutoSetup\' -ErrorAction Stop
    Write-Log "đã tạo và chạy tác vụ \AutoSetup\$taskName"
} catch {
    Write-Log "LỖI tạo tác vụ: $($_.Exception.Message). Chạy thẳng SauCai.ps1."
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -TuDong' -f (Join-Path $goc 'sau-cai\SauCai.ps1'))
}
exit 0
