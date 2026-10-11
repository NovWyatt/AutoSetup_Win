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

function Test-OfficeInstalled {
    return [bool](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue)
}

function Install-OfficeFromUsb {
    # Cài Office bằng Office Deployment Tool để sẵn trên USB (\AutoSetup\office: setup.exe + file .xml, có thể kèm
    # thư mục Office\Data để cài không cần mạng). Trả @{ TrangThai; GhiChu }.
    param([string]$UsbRoot, [bool]$HasInternet, [switch]$DryRun)
    if (-not $UsbRoot) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = 'Không thấy USB AutoSetup.' } }
    $dir = Join-Path $UsbRoot 'AutoSetup\office'
    $setup = Join-Path $dir 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = 'Không có bộ cài Office trên USB (\AutoSetup\office\setup.exe).' } }
    if (Test-OfficeInstalled) { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = 'Office (Click-to-Run) đã có.' } }
    $xml = Join-Path $dir 'cau-hinh.xml'
    if (-not (Test-Path -LiteralPath $xml)) { $xml = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File | Sort-Object Name | Select-Object -First 1 | ForEach-Object { $_.FullName })[0] }
    if (-not $xml) { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = 'Có setup.exe nhưng thiếu file cấu hình .xml.' } }
    $offline = Test-Path -LiteralPath (Join-Path $dir 'Office\Data')
    if (-not $offline -and -not $HasInternet) { return [pscustomobject]@{ TrangThai = 'cho-mang'; GhiChu = 'Bộ cài Office không có sẵn file (Office\Data), cần mạng để tải.' } }
    Write-Info ("Cài Office theo {0}{1}" -f (Split-Path -Leaf $xml), $(if ($offline) { ' (file có sẵn trên USB)' } else { ' (tải từ Microsoft)' }))
    if ($DryRun) { Write-Plan "`"$setup`" /configure `"$xml`""; return [pscustomobject]@{ TrangThai = 'chay-thu'; GhiChu = '' } }
    $p = Start-Process -FilePath $setup -ArgumentList ('/configure "{0}"' -f $xml) -WorkingDirectory $dir -Wait -PassThru
    if (Test-OfficeInstalled) { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = "Đã cài Office ($(Split-Path -Leaf $xml))." } }
    return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "setup.exe /configure mã $($p.ExitCode), chưa thấy Office. Xem nhật ký trong %TEMP% (tên máy-*.log)." }
}

function Get-MachineInfo {
    # Thông tin máy cho báo cáo (không có khoá sản phẩm).
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $lic = @(Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1)
    $licText = @{ 0 = 'chưa có giấy phép'; 1 = 'đã kích hoạt'; 2 = 'ân hạn OOB'; 3 = 'ân hạn OOT'; 4 = 'không chính hãng'; 5 = 'thông báo'; 6 = 'ân hạn mở rộng' }
    $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter | ForEach-Object {
            [pscustomobject]@{ o = "$($_.DriveLetter):"; nhan = [string]$_.FileSystemLabel; loai = [string]$_.DriveType; dungLuongGB = [math]::Round($_.Size / 1GB, 1); conTrongGB = [math]::Round($_.SizeRemaining / 1GB, 1) } })
    $bl = @()
    try { $bl = @(Get-BitLockerVolume -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ o = $_.MountPoint; baoVe = [string]$_.ProtectionStatus; maHoa = [string]$_.VolumeStatus } }) } catch { }
    return [pscustomobject]@{
        tenMay     = $env:COMPUTERNAME
        hang       = [string]$cs.Manufacturer
        model      = [string]$cs.Model
        serial     = [string]$bios.SerialNumber
        windows    = ('{0} ({1})' -f $os.Caption, $os.Version)
        banQuyen   = $(if ($lic.Count) { '{0}: {1}' -f $lic[0].Name, $licText[[int]$lic[0].LicenseStatus] } else { 'không đọc được' })
        ramGB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        oDia       = $vols
        bitLocker  = $bl
    }
}
