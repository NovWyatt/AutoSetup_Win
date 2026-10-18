<#
  Mạng, ổ dữ liệu, Office, tên máy, thông tin máy cho báo cáo.
#>

function Test-Internet {
    # Có Internet không: trang kiểm tra kết nối của Windows (msftconnecttest) trả đúng nội dung.
    if ($env:AUTOSETUP_TEST_MANG) { return ($env:AUTOSETUP_TEST_MANG -eq '1') }
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
        return ($r.Content -match 'Microsoft Connect Test')
    } catch { return $false }
}

function Wait-Internet {
    # Đợi có mạng tối đa $Minutes phút, nhắc cắm dây hoặc bắt Wi-Fi. Trả $true khi có mạng.
    param([int]$Minutes = 10)
    if (Test-Internet) { return $true }
    if ($Minutes -le 0 -or $env:AUTOSETUP_TEST_MANG) { return $false }   # bài thử giả mạng: không đợi
    Write-Warn "Chưa có Internet. Cắm dây mạng hoặc bấm biểu tượng mạng ở góc phải để bắt Wi-Fi; đợi tối đa $Minutes phút."
    $deadline = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        if (Test-Internet) { Write-Ok 'Đã có Internet.'; return $true }
    }
    Write-Warn 'Vẫn chưa có Internet: bỏ qua các bước cần mạng (chạy lại bằng CHAY_LAI.bat khi có mạng).'
    return $false
}

function Get-FreeLetter {
    # Chữ ổ trống đầu tiên từ Z ngược về E (để chữ đầu bảng cho ổ của người dùng).
    $used = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToUpperInvariant() })
    $used += @(Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter.Substring(0, 1).ToUpperInvariant() })
    foreach ($c in [char[]]'ZYXWVUTSRQPONMLKJIHGFE') { if ([string]$c -notin $used) { return [string]$c } }
    return $null
}

function Invoke-StorageFunction {
    # Chạy một hàm dùng lệnh Storage (Get-Partition, Get-Disk, Get-Volume, Get-BitLockerVolume) trong tiến trình
    # powershell.exe riêng (lib\ChayRieng.ps1, cùng cửa sổ); quá $TimeoutSeconds thì dừng tiến trình đó. Lệnh Storage nhờ
    # dịch vụ smphost: dịch vụ không bật được thì lệnh đứng mãi, không ngắt được trong cùng tiến trình (thử máy ảo
    # 18/10/2026: PushToInstall kẹt START_PENDING, Get-Partition đứng 45 phút). Đã quá giờ một lần thì các lần sau trong
    # lượt chạy này trả quá giờ ngay, khỏi chờ thêm. Trả @{ QuaGio; KetQua; Loi; Pid }.
    param([Parameter(Mandatory)][string]$Name, [int]$TimeoutSeconds = 300, [switch]$DryRun)
    if ($script:StorageTreo) { return [pscustomobject]@{ QuaGio = $true; KetQua = $null; Loi = ''; Pid = 0 } }
    $out = Join-Path ([IO.Path]::GetTempPath()) ('AutoSetup_{0}.xml' -f [guid]::NewGuid().ToString('N'))
    $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Ham {1} -Ra "{2}"{3}' -f (Join-Path $PSScriptRoot 'ChayRieng.ps1'), $Name, $out, $(if ($DryRun) { ' -ChayThu' })
    $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argText -NoNewWindow -PassThru
    $null = $p.Handle   # giữ handle để đọc được ExitCode sau khi thoát (PowerShell 5.1)
    try {
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
            [void]$p.WaitForExit(10000)
            $script:StorageTreo = $true
            return [pscustomobject]@{ QuaGio = $true; KetQua = $null; Loi = ''; Pid = $p.Id }
        }
        if (-not (Test-Path -LiteralPath $out)) { return [pscustomobject]@{ QuaGio = $false; KetQua = $null; Loi = "tiến trình đọc ổ đĩa thoát mã $($p.ExitCode), không trả kết quả"; Pid = $p.Id } }
        $r = Import-Clixml -LiteralPath $out
        return [pscustomobject]@{ QuaGio = $false; KetQua = $r.KetQua; Loi = [string]$r.Loi; Pid = $p.Id }
    } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
}

function Get-DataPartitionCandidates {
    # Phân vùng dữ liệu trên ổ trong (không phải USB, thẻ nhớ): Basic/IFS, không ẩn, > 1 GB, có hệ thống file, không phải C.
    $winDisk = $null
    try { $winDisk = (Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction Stop).DiskNumber } catch { }
    $out = @()
    foreach ($p in @(Get-Partition -ErrorAction SilentlyContinue)) {
        if ($p.Type -notin 'Basic', 'IFS' -or $p.IsHidden -or $p.Size -lt 1GB) { continue }
        if ([string]$p.DriveLetter -eq $env:SystemDrive.Substring(0, 1)) { continue }
        $disk = Get-Disk -Number $p.DiskNumber -ErrorAction SilentlyContinue
        if (-not $disk -or $disk.BusType -in 'USB', 'SD', 'MMC', 'File Backed Virtual') { continue }
        $vol = $p | Get-Volume -ErrorAction SilentlyContinue
        if (-not $vol -or $vol.FileSystem -notin 'NTFS', 'ReFS', 'exFAT') { continue }
        $out += [pscustomobject]@{ Partition = $p; Volume = $vol; Label = [string]$vol.FileSystemLabel; Letter = [string]$p.DriveLetter; WindowsDisk = ($p.DiskNumber -eq $winDisk) }
    }
    return , $out
}

function Set-DataDriveLetter {
    # Đưa phân vùng dữ liệu về chữ D (USB, ổ CD hay chiếm D lúc cài). Trả @{ TrangThai; GhiChu }.
    param([switch]$DryRun)
    $c = Get-DataPartitionCandidates
    if (-not $c.Count) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = 'Máy không có phân vùng dữ liệu ngoài C.' } }
    if ($c.Count -gt 1) {
        $data = @($c | Where-Object { $_.Label -eq 'DATA' })
        if ($data.Count -ne 1) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = "Có $($c.Count) phân vùng dữ liệu, không tự đổi chữ ổ." } }
        $c = $data
    }
    $t = $c[0]
    if ($t.Letter -eq 'D') { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = "Phân vùng dữ liệu đã là D ($($t.Label))." } }
    $holderVol = Get-CimInstance Win32_Volume -Filter "DriveLetter='D:'" -ErrorAction SilentlyContinue
    $holderPart = Get-Partition -DriveLetter D -ErrorAction SilentlyContinue
    if ($holderPart) {
        $hd = Get-Disk -Number $holderPart.DiskNumber -ErrorAction SilentlyContinue
        if ($hd -and $hd.BusType -notin 'USB', 'SD', 'MMC') { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = 'Chữ D đang là một ổ trong khác, không đổi.' } }
    }
    $plan = @()
    $newHolder = $null
    if ($holderVol) {
        $newHolder = Get-FreeLetter
        if (-not $newHolder) { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = 'Không còn chữ ổ trống để chuyển ổ đang chiếm D.' } }
        $plan += "Đổi ổ đang chiếm D ($($holderVol.Label)) sang $newHolder"
    }
    $plan += "Đổi phân vùng dữ liệu $(if ($t.Letter) { $t.Letter } else { '(chưa có chữ)' }) ($($t.Label)) thành D"
    foreach ($s in $plan) { Write-Plan $s }
    if ($DryRun) { return [pscustomobject]@{ TrangThai = 'chay-thu'; GhiChu = ($plan -join '; ') } }
    try {
        if ($holderVol) {
            if ($holderPart) { Set-Partition -DiskNumber $holderPart.DiskNumber -PartitionNumber $holderPart.PartitionNumber -NewDriveLetter $newHolder -ErrorAction Stop }
            else { $holderVol | Set-CimInstance -Property @{ DriveLetter = "${newHolder}:" } -ErrorAction Stop }
        }
        Set-Partition -DiskNumber $t.Partition.DiskNumber -PartitionNumber $t.Partition.PartitionNumber -NewDriveLetter D -ErrorAction Stop
        return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = ($plan -join '; ') }
    } catch { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "Đổi chữ ổ lỗi: $($_.Exception.Message.Trim())" } }
}

function Invoke-DataDriveLetter {
    # Set-DataDriveLetter có giới hạn thời gian (chạy qua Invoke-StorageFunction). Trả @{ TrangThai; GhiChu; QuaGio };
    # quá giờ thì Invoke-StepODuLieu quyết định khởi động lại hay báo lỗi.
    param([int]$TimeoutSeconds = 300, [switch]$DryRun)
    Write-Info "Đọc phân vùng ổ đĩa (dừng nếu quá $(Format-Seconds $TimeoutSeconds))..."
    $r = Invoke-StorageFunction 'Set-DataDriveLetter' -TimeoutSeconds $TimeoutSeconds -DryRun:$DryRun
    if ($r.QuaGio) {
        return [pscustomobject]@{ TrangThai = 'loi'; QuaGio = $true; GhiChu = "Lệnh đọc ổ đĩa của Windows đứng quá $(Format-Seconds $TimeoutSeconds) (dịch vụ Storage của Windows không bật được), đã dừng." }
    }
    if ($r.Loi) { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "Đọc phân vùng lỗi: $($r.Loi)" } }
    return [pscustomobject]@{ TrangThai = [string]$r.KetQua.TrangThai; GhiChu = [string]$r.KetQua.GhiChu }
}

function Test-OfficeInstalled {
    return [bool](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue)
}

$script:OdtUrl = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'   # Office Deployment Tool bản mới nhất của Microsoft

function Test-MicrosoftSignature {
    # File có chữ ký số hợp lệ của Microsoft Corporation (kiểm setup.exe tải về trước khi chạy bằng quyền Admin).
    param([string]$Path)
    $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction SilentlyContinue
    return [bool]($s -and $s.Status -eq 'Valid' -and $s.SignerCertificate -and $s.SignerCertificate.Subject -match '(^|, )O=Microsoft Corporation(,|$)')
}

function Install-Office {
    # Cài Office bằng Office Deployment Tool (ODT). Ưu tiên bộ cài để sẵn trên USB (\AutoSetup\office: setup.exe + file
    # .xml, có thể kèm Office\Data để cài không cần mạng). Không có thì tải setup.exe của Microsoft vào $WorkDir (kiểm chữ
    # ký) rồi cài theo $ConfigXml (cau-hinh\Office.xml), Office tải từ Microsoft nên cần mạng. Trả @{ TrangThai; GhiChu }.
    param([string]$UsbRoot, [string]$ConfigXml, [string]$WorkDir, [bool]$HasInternet, [switch]$DryRun)
    if (Test-OfficeInstalled) { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = 'Office (Click-to-Run) đã có.' } }
    $dir = if ($UsbRoot) { Join-Path $UsbRoot 'AutoSetup\office' } else { '' }
    $setup = if ($dir) { Join-Path $dir 'setup.exe' } else { '' }
    $download = $false
    if ($setup -and (Test-Path -LiteralPath $setup)) {
        $xml = Join-Path $dir 'cau-hinh.xml'
        if (-not (Test-Path -LiteralPath $xml)) { $xml = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File | Sort-Object Name | Select-Object -First 1 | ForEach-Object { $_.FullName })[0] }
        if (-not $xml) { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = 'Có setup.exe nhưng thiếu file cấu hình .xml.' } }
        $offline = Test-Path -LiteralPath (Join-Path $dir 'Office\Data')
    } else {
        if (-not $ConfigXml -or -not (Test-Path -LiteralPath $ConfigXml)) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = 'Không có bộ cài Office trên USB (\AutoSetup\office\setup.exe), cũng không có cau-hinh\Office.xml.' } }
        $xml = $ConfigXml
        $offline = $false
        $download = $true
        $dir = $WorkDir
        $setup = Join-Path $WorkDir 'setup.exe'
    }
    if (-not $offline -and -not $HasInternet) { return [pscustomobject]@{ TrangThai = 'cho-mang'; GhiChu = 'Cần mạng để tải Office từ Microsoft.' } }
    Write-Info ("Cài Office theo {0}{1}" -f (Split-Path -Leaf $xml), $(if ($offline) { ' (file có sẵn trên USB)' } else { ' (tải từ Microsoft, khoảng 2-3 GB)' }))
    if ($DryRun) {
        if ($download) { Write-Plan "Tải Office Deployment Tool $($script:OdtUrl) vào $WorkDir" }
        Write-Plan "`"$setup`" /configure `"$xml`""
        return [pscustomobject]@{ TrangThai = 'chay-thu'; GhiChu = '' }
    }
    if ($download) {
        try {
            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $script:OdtUrl -OutFile $setup -UseBasicParsing -TimeoutSec 300
        } catch { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "Tải Office Deployment Tool lỗi: $($_.Exception.Message.Trim())" } }
        if (-not (Test-MicrosoftSignature $setup)) {
            Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = 'setup.exe tải về không có chữ ký hợp lệ của Microsoft, không chạy.' }
        }
    }
    $p = Start-Process -FilePath $setup -ArgumentList ('/configure "{0}"' -f $xml) -WorkingDirectory $dir -Wait -PassThru
    if (Test-OfficeInstalled) { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = "Đã cài Office ($(Split-Path -Leaf $xml))." } }
    return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "setup.exe /configure mã $($p.ExitCode), chưa thấy Office. Xem nhật ký trong %TEMP% (tên máy-*.log)." }
}

function Get-DiskInfo {
    # Ổ đĩa, BitLocker cho báo cáo. Get-Volume và Get-BitLockerVolume đều đọc MSFT_Volume qua smphost nên Get-MachineInfo
    # gọi hàm này qua Invoke-StorageFunction.
    $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter | ForEach-Object {
            [pscustomobject]@{ o = "$($_.DriveLetter):"; nhan = [string]$_.FileSystemLabel; loai = [string]$_.DriveType; dungLuongGB = [math]::Round($_.Size / 1GB, 1); conTrongGB = [math]::Round($_.SizeRemaining / 1GB, 1) } })
    $bl = @()
    try { $bl = @(Get-BitLockerVolume -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ o = $_.MountPoint; baoVe = [string]$_.ProtectionStatus; maHoa = [string]$_.VolumeStatus } }) } catch { }
    return [pscustomobject]@{ oDia = $vols; bitLocker = $bl }
}

function Get-MachineInfo {
    # Thông tin máy cho báo cáo (không có khoá sản phẩm). Đọc ổ đĩa quá $DiskTimeoutSeconds thì báo cáo ghi oDiaLoi.
    param([int]$DiskTimeoutSeconds = 300)
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $lic = @(Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1)
    # LicenseStatus: 2 OOB grace, 3 OOT grace (đổi phần cứng), 5 Notification (hết ân hạn, nhắc kích hoạt), 6 ân hạn mở rộng.
    $licText = @{ 0 = 'chưa có giấy phép'; 1 = 'đã kích hoạt'; 2 = 'chưa kích hoạt (đang trong thời gian ân hạn)'; 3 = 'chưa kích hoạt (ân hạn do đổi phần cứng)'
        4 = 'không chính hãng'; 5 = 'chưa kích hoạt (Windows nhắc kích hoạt)'; 6 = 'chưa kích hoạt (ân hạn mở rộng)' }
    $disk = Invoke-StorageFunction 'Get-DiskInfo' -TimeoutSeconds $DiskTimeoutSeconds
    $vols = @(); $bl = @(); $diskErr = ''
    if ($disk.QuaGio) { $diskErr = "không đọc được: lệnh đọc ổ đĩa của Windows đứng quá $(Format-Seconds $DiskTimeoutSeconds)" }
    elseif ($disk.Loi -or -not $disk.KetQua) { $diskErr = "không đọc được: $($disk.Loi)" }
    else { $vols = @($disk.KetQua.oDia); $bl = @($disk.KetQua.bitLocker) }
    return [pscustomobject]@{
        tenMay     = $env:COMPUTERNAME
        hang       = [string]$cs.Manufacturer
        model      = [string]$cs.Model
        serial     = [string]$bios.SerialNumber
        windows    = ('{0} ({1})' -f $os.Caption, $os.Version)
        banQuyen   = $(if ($lic.Count) { '{0}: {1}' -f $lic[0].Name, $licText[[int]$lic[0].LicenseStatus] } else { 'không đọc được' })
        ramGB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        oDia       = $vols
        oDiaLoi    = $diskErr
        bitLocker  = $bl
    }
}

function Remove-LsaSecret {
    # Xoá một bí mật LSA (LsaStorePrivateData với dữ liệu NULL), cần quyền Admin. Windows Setup cất mật khẩu tự đăng
    # nhập của unattend trong bí mật "DefaultPassword", không phải trong registry. Trả mã lỗi Win32: 0 đã xoá,
    # 2 vốn không có, 5 không đủ quyền. FirstLogon.ps1 có bản sao của hàm này (script đó chạy một mình).
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
