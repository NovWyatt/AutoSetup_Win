<#
  AutoSetup_Win - bước specialize (quyền SYSTEM, trước khi có tài khoản nào).
  Đọc AutoSetup.json cùng thư mục (sinh từ cau-hinh\CauHinh.json lúc dựng file unattend):
    - gỡ ứng dụng cài sẵn (gói Appx provisioned) theo goBo.ungDung, capability theo goBo.capability,
      tắt tính năng theo goBo.tinhNang, bỏ bộ cài OneDrive;
    - đặt chính sách cấp máy theo tinhChinh và oobe.
  Không dừng khi một mục lỗi: ghi vào Specialize.log rồi làm mục tiếp theo (Setup không được hỏng vì một ứng dụng).
#>
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'Specialize.log'

function Write-Log {
    param([string]$Text)
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $Text
    [IO.File]::AppendAllText($logFile, $line + "`r`n", (New-Object Text.UTF8Encoding $true))
}

function Set-Reg {
    # Ghi một giá trị registry (tạo khoá nếu chưa có). $Path dạng HKLM\SOFTWARE\...
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        $p = "Registry::$Path"
        if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -Force | Out-Null }
        New-ItemProperty -LiteralPath $p -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log "registry $Path\$Name = $Value"
    } catch { Write-Log "LỖI registry $Path\$Name`: $($_.Exception.Message)" }
}

function Test-On {
    # Cờ bật/tắt trong cấu hình (không có thì coi là tắt).
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    $p = $Object.PSObject.Properties[$Name]
    return ($p -and $p.Value -eq $true)
}

Write-Log '=== Bắt đầu specialize ==='
try { $cfg = [IO.File]::ReadAllText((Join-Path $here 'AutoSetup.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json }
catch { Write-Log "LỖI đọc AutoSetup.json: $($_.Exception.Message). Bỏ qua bước specialize."; exit 0 }

# ---------------------------------------------------------------- gỡ ứng dụng cài sẵn
$names = @($cfg.goBo.ungDung | Where-Object { $_ })
if ($names.Count) {
    try {
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        foreach ($n in $names) {
            $hit = @($prov | Where-Object { $_.DisplayName -eq $n })
            if (-not $hit.Count) { Write-Log "ứng dụng ${n}: không có sẵn trong bản Windows này"; continue }
            foreach ($h in $hit) {
                try { Remove-AppxProvisionedPackage -Online -PackageName $h.PackageName -AllUsers -ErrorAction Stop | Out-Null; Write-Log "đã gỡ ứng dụng $n" }
                catch { Write-Log "LỖI gỡ ứng dụng $n`: $($_.Exception.Message)" }
            }
        }
    } catch { Write-Log "LỖI đọc danh sách ứng dụng cài sẵn: $($_.Exception.Message)" }
}

$caps = @($cfg.goBo.capability | Where-Object { $_ })
if ($caps.Count) {
    try {
        $installed = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.State -eq 'Installed' })
        foreach ($c in $caps) {
            $hit = @($installed | Where-Object { $_.Name -eq $c -or $_.Name -like "$c~*" })
            if (-not $hit.Count) { Write-Log "capability ${c}: chưa cài"; continue }
            foreach ($h in $hit) {
                try { Remove-WindowsCapability -Online -Name $h.Name -ErrorAction Stop | Out-Null; Write-Log "đã gỡ capability $($h.Name)" }
                catch { Write-Log "LỖI gỡ capability $($h.Name): $($_.Exception.Message)" }
            }
        }
    } catch { Write-Log "LỖI đọc danh sách capability: $($_.Exception.Message)" }
}

foreach ($f in @($cfg.goBo.tinhNang | Where-Object { $_ })) {
    try {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop
        if ($feat.State -in 'Enabled', 'EnablePending') {
            Disable-WindowsOptionalFeature -Online -FeatureName $f -Remove -NoRestart -ErrorAction Stop | Out-Null
            Write-Log "đã tắt tính năng $f"
        } else { Write-Log "tính năng $f đang $($feat.State)" }
    } catch { Write-Log "tính năng $f`: không có hoặc lỗi ($($_.Exception.Message))" }
}

if (Test-On $cfg.goBo 'oneDrive') {
    # Lối tắt cài OneDrive của tài khoản mới nằm ở hive Default (DefaultUser.ps1 xoá). Ở đây bỏ bộ cài và lối tắt Start.
    foreach ($p in 'C:\Windows\System32\OneDriveSetup.exe', 'C:\Windows\SysWOW64\OneDriveSetup.exe', 'C:\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk') {
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; Write-Log "đã xoá $p" }
            catch { Write-Log "không xoá được $p ($($_.Exception.Message)); OneDrive vẫn không tự cài vì đã bỏ khỏi Run của tài khoản mới" }
        }
    }
}

# ---------------------------------------------------------------- chính sách cấp máy
$t = $cfg.tinhChinh
if (Test-On $cfg.oobe 'choCaiKhongMang') { Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 1 }
if (Test-On $t 'tatWidgets') { Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 }
if (Test-On $t 'tatGoiYUngDung') { Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 }
if (Test-On $t 'tatCopilot') { Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 }
if (Test-On $t 'chanTuMaHoaO') { Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1 }
if (Test-On $t 'anEdgeLanDau') { Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1 }
if (Test-On $t 'batDuongDanDai') { Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 }

Write-Log '=== Xong specialize ==='
exit 0
