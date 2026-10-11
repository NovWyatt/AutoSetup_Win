<#
  AutoSetup_Win - chỉnh hive của tài khoản mẫu (C:\Users\Default\NTUSER.DAT), chạy ở bước specialize.
  Bước trước đã nạp hive vào HKU\DefaultUser (reg load), bước sau gỡ ra (reg unload). Mọi tài khoản tạo về sau
  (kể cả tài khoản đầu tiên tạo ở OOBE) đều nhận các thiết lập này, không chỉ tài khoản đầu tiên.
#>
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'DefaultUser.log'
$root = 'HKEY_USERS\DefaultUser'
$searchModes = @{ 'an' = 0; 'icon' = 1; 'o' = 2; 'nhan' = 3 }

function Write-Log {
    param([string]$Text)
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $Text
    [IO.File]::AppendAllText($logFile, $line + "`r`n", (New-Object Text.UTF8Encoding $true))
}

function Set-UserReg {
    # Ghi giá trị vào hive mẫu. $Sub là đường dẫn tính từ gốc tài khoản (vd Software\Microsoft\...).
    param([string]$Sub, [string]$Name, $Value, [string]$Type = 'DWord')
    $p = "Registry::$root\$Sub"
    try {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -Force | Out-Null }
        New-ItemProperty -LiteralPath $p -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log "HKCU\$Sub\$Name = $Value"
    } catch { Write-Log "LỖI HKCU\$Sub\$Name`: $($_.Exception.Message)" }
}

function Test-On {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    $p = $Object.PSObject.Properties[$Name]
    return ($p -and $p.Value -eq $true)
}

Write-Log '=== Bắt đầu chỉnh tài khoản mẫu ==='
if (-not (Test-Path -LiteralPath "Registry::$root")) { Write-Log "LỖI: chưa nạp hive $root, bỏ qua."; exit 0 }
try { $cfg = [IO.File]::ReadAllText((Join-Path $here 'AutoSetup.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json }
catch { Write-Log "LỖI đọc AutoSetup.json: $($_.Exception.Message). Bỏ qua."; exit 0 }
$t = $cfg.tinhChinh
$adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

if (Test-On $t 'hienDuoiFile') { Set-UserReg $adv 'HideFileExt' 0 }
if (Test-On $t 'moThisPC') { Set-UserReg $adv 'LaunchTo' 1 }
if (Test-On $t 'taskbarTrai') { Set-UserReg $adv 'TaskbarAl' 0 }
if (Test-On $t 'anTaskView') { Set-UserReg $adv 'ShowTaskViewButton' 0 }
if (Test-On $t 'hienEndTask') { Set-UserReg "$adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1 }
if ($t -and $t.timKiem -and $searchModes.ContainsKey([string]$t.timKiem)) {
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' $searchModes[[string]$t.timKiem]
}
if (Test-On $t 'tatBingTrongStart') { Set-UserReg 'Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 }
if (Test-On $t 'tatCopilot') { Set-UserReg 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 }
if (Test-On $t 'tatGoiYUngDung') {
    # Không tự cài ứng dụng "gợi ý" (game, ứng dụng quảng cáo) và không hiện gợi ý trong Start, Cài đặt, màn hình khoá.
    $cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
        'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
        'SubscribedContentEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
        'SubscribedContent-353698Enabled', 'RotatingLockScreenOverlayEnabled') {
        Set-UserReg $cdm $n 0
    }
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
}
if (Test-On $t 'menuChuotPhaiCu') {
    $p = "Registry::$root\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    try { New-Item -Path $p -Force | Out-Null; Set-Item -LiteralPath $p -Value ''; Write-Log 'menu chuột phải kiểu cũ: bật' }
    catch { Write-Log "LỖI menu chuột phải kiểu cũ: $($_.Exception.Message)" }
}
if (Test-On $cfg.goBo 'oneDrive') {
    $run = "Registry::$root\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        if (Get-ItemProperty -LiteralPath $run -Name 'OneDriveSetup' -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -LiteralPath $run -Name 'OneDriveSetup' -ErrorAction Stop
            Write-Log 'đã bỏ OneDriveSetup khỏi Run của tài khoản mẫu'
        }
    } catch { Write-Log "LỖI bỏ OneDriveSetup: $($_.Exception.Message)" }
}

# Đóng mọi handle tới hive để bước sau gỡ được (reg unload).
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
Write-Log '=== Xong chỉnh tài khoản mẫu ==='
exit 0
