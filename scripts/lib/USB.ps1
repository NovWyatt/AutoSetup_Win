<#
  Hàm cho giao diện tạo USB (scripts\GiaoDienUSB.ps1): tìm USB, nhận biết Ventoy, tải Ventoy, liệt kê ISO, ghi cấu
  hình riêng. Hàm không đụng máy (ConvertTo-*, Select-*, Set-*) để bài thử truyền dữ liệu giả.
#>

. (Join-Path $PSScriptRoot '..\..\sau-cai\lib\Json.ps1')

# Tên ISO cứu hộ hay gặp (WinPE kèm công cụ): chỉ để ghi loại cho dễ nhìn, Ventoy khởi động như ISO thường.
$script:RescueIso = '(?i)anhdv|hiren|strelec|dlc[ ._-]?boot|medicat|winpe|[ ._-]pe[ ._-]'

$script:VentoyApi = if ($env:AUTOSETUP_GITHUB_API) { $env:AUTOSETUP_GITHUB_API } else { 'https://api.github.com' }

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Get-DiskInventory {
    # Ổ đĩa và phân vùng của máy, dạng đối tượng đơn giản cho ConvertTo-UsbDiskList (không cần quyền quản trị).
    $disks = @(Get-Disk -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ Number = [int]$_.Number; BusType = [string]$_.BusType; FriendlyName = [string]$_.FriendlyName
                Size = [double]$_.Size; IsBoot = [bool]$_.IsBoot; IsSystem = [bool]$_.IsSystem; PartitionStyle = [string]$_.PartitionStyle }
        })
    $parts = @(Get-Partition -ErrorAction SilentlyContinue | ForEach-Object {
            $vol = $_ | Get-Volume -ErrorAction SilentlyContinue
            [pscustomobject]@{ DiskNumber = [int]$_.DiskNumber; PartitionNumber = [int]$_.PartitionNumber
                DriveLetter = $(if ($_.DriveLetter -and $_.DriveLetter -ne [char]0) { [string]$_.DriveLetter } else { '' })
                Label = $(if ($vol) { [string]$vol.FileSystemLabel } else { '' }); Size = [double]$_.Size
                Free = $(if ($vol) { [double]$vol.SizeRemaining } else { 0 }) }
        })
    return [pscustomobject]@{ Disks = $disks; Partitions = $parts }
}

function ConvertTo-UsbDiskList {
    # Ổ làm được USB cài Windows (trả từng ổ, gọi bằng @(...)): bus USB, SD, MMC; bỏ ổ khởi động, ổ hệ thống. Ventoy nhận ra qua phân vùng nhãn
    # VTOYEFI; ODuLieu là gốc phân vùng dữ liệu ('E:\') nếu có chữ ổ.
    param($Inventory)
    foreach ($d in @($Inventory.Disks | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)) {
        $parts = @($Inventory.Partitions | Where-Object { $_.DiskNumber -eq $d.Number } | Sort-Object PartitionNumber)
        $ventoy = [bool]@($parts | Where-Object { $_.Label -eq 'VTOYEFI' }).Count
        $data = if ($ventoy) { @($parts | Where-Object { $_.Label -ne 'VTOYEFI' }) | Select-Object -First 1 } else { @($parts | Where-Object { $_.DriveLetter }) | Select-Object -First 1 }
        $root = if ($data -and $data.DriveLetter) { '{0}:\' -f $data.DriveLetter } else { '' }
        [pscustomobject]@{
            So = $d.Number; Ten = $d.FriendlyName.Trim(); KichThuoc = $d.Size; KichThuocChu = Format-Size $d.Size; Bus = $d.BusType
            Ventoy = $ventoy; VentoyChu = $(if ($ventoy) { 'Đã có' } else { 'Chưa có' }); ODuLieu = $root
            ConTrong = $(if ($data) { Format-Size $data.Free } else { '' })
        }
    }
}

function Get-ShaFromDigest {
    # GitHub ghi mã băm của tệp phát hành dạng "sha256:<64 hex>". Trả chuỗi hex thường hoặc ''.
    param([string]$Digest)
    if ($Digest -match '^sha256:([0-9a-fA-F]{64})$') { return $Matches[1].ToLowerInvariant() }
    return ''
}

function Get-ShaFromList {
    # Dòng "<64 hex>  <tên tệp>" trong sha256.txt của Ventoy. Trả chuỗi hex thường hoặc ''.
    param([string]$Text, [string]$FileName)
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $FileName) { return $Matches[1].ToLowerInvariant() }
    }
    return ''
}

function Select-VentoyAsset {
    # Từ bản phát hành GitHub của ventoy/Ventoy: @{ PhienBan; Ten; Url; Sha256; Sha256Url } của gói Windows, $null nếu thiếu.
    param($Release)
    $zip = @($Release.assets | Where-Object { $_.name -match '^ventoy-(\d+(\.\d+)+)-windows\.zip$' }) | Select-Object -First 1
    if (-not $zip) { return $null }
    [void]($zip.name -match '^ventoy-(\d+(\.\d+)+)-windows\.zip$')
    $ver = $Matches[1]
    $list = @($Release.assets | Where-Object { $_.name -eq 'sha256.txt' }) | Select-Object -First 1
    return [pscustomobject]@{
        PhienBan = $ver; Ten = $zip.name; Url = $zip.browser_download_url; Sha256 = Get-ShaFromDigest ([string]$zip.digest)
        Sha256Url = $(if ($list) { $list.browser_download_url } else { '' })
    }
}

function Find-CachedVentoy {
    # Ventoy2Disk.exe mới nhất đã giải nén trong $CacheDir (ventoy-<phiên bản>\Ventoy2Disk.exe), '' nếu chưa có.
    param([string]$CacheDir)
    if (-not (Test-Path -LiteralPath $CacheDir)) { return '' }
    $best = @(Get-ChildItem -LiteralPath $CacheDir -Directory -Filter 'ventoy-*' | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Ventoy2Disk.exe') } |
            Sort-Object { try { [version]($_.Name -replace '^ventoy-', '') } catch { [version]'0.0' } } -Descending) | Select-Object -First 1
    if ($best) { return (Join-Path $best.FullName 'Ventoy2Disk.exe') }
    return ''
}

function Install-VentoyTool {
    # Ventoy2Disk.exe sẵn dùng: tải bản mới nhất từ GitHub vào $CacheDir nếu chưa có (chỉ dùng khi SHA-256 khớp mã băm
    # GitHub hoặc sha256.txt của Ventoy), không có mạng thì dùng bản đã tải. $Log: scriptblock nhận một dòng chữ.
    param([Parameter(Mandatory)][string]$CacheDir, [scriptblock]$Log = { param($t) Write-Host "  $t" })
    $cached = Find-CachedVentoy $CacheDir
    $tmp = ''
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod -Uri "$($script:VentoyApi)/repos/ventoy/Ventoy/releases/latest" -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'AutoSetup_Win' }
        $a = Select-VentoyAsset $rel
        if (-not $a) { throw 'bản phát hành mới nhất không có gói Windows' }
        $dir = Join-Path $CacheDir "ventoy-$($a.PhienBan)"
        $exe = Join-Path $dir 'Ventoy2Disk.exe'
        if (Test-Path -LiteralPath $exe) { & $Log "Ventoy $($a.PhienBan) đã tải từ trước."; return $exe }
        $want = $a.Sha256
        if (-not $want -and $a.Sha256Url) {
            $raw = (Invoke-WebRequest -Uri $a.Sha256Url -UseBasicParsing -TimeoutSec 30).Content
            if ($raw -is [byte[]]) { $raw = [Text.Encoding]::ASCII.GetString($raw) }
            $want = Get-ShaFromList ([string]$raw) $a.Ten
        }
        if (-not $want) { throw "không có mã băm SHA-256 cho $($a.Ten)" }
        & $Log "Tải $($a.Ten) từ GitHub (ventoy/Ventoy)..."
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        $tmp = Join-Path $CacheDir ('{0}.tai-{1}' -f $a.Ten, [guid]::NewGuid().ToString('N').Substring(0, 8))
        Invoke-WebRequest -Uri $a.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 600
        $got = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($got -ne $want) { throw "tệp tải về sai mã băm (được $got, cần $want)" }
        $unz = "$dir.giai-nen"
        if (Test-Path -LiteralPath $unz) { Remove-Item -LiteralPath $unz -Recurse -Force }
        Expand-Archive -LiteralPath $tmp -DestinationPath $unz -Force
        # Gói có một thư mục ventoy-<phiên bản>\ bên trong.
        $inner = @(Get-ChildItem -LiteralPath $unz -Recurse -Filter 'Ventoy2Disk.exe' -File) | Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $inner) { throw 'gói tải về không có Ventoy2Disk.exe' }
        Move-Item -LiteralPath $inner.Directory.FullName -Destination $dir
        Remove-Item -LiteralPath $unz -Recurse -Force -ErrorAction SilentlyContinue
        & $Log "Đã tải Ventoy $($a.PhienBan), mã băm SHA-256 khớp."
        return $exe
    } catch {
        if ($cached) { & $Log "Không tải được Ventoy mới ($($_.Exception.Message.Trim())), dùng bản đã tải: $cached"; return $cached }
        throw "Không tải được Ventoy: $($_.Exception.Message.Trim())"
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Get-Ventoy2DiskArgs {
    # Tham số dòng lệnh Ventoy2Disk (VTOYCLI): Lenh I = cài mới (xoá sạch USB), U = cập nhật (giữ dữ liệu).
    param([ValidateSet('I', 'U')][string]$Lenh, [int]$So, [switch]$Gpt, [switch]$KhongSecureBoot)
    $a = @('VTOYCLI', "/$Lenh", "/PhyDrive:$So")
    if ($Gpt -and $Lenh -eq 'I') { $a += '/GPT' }
    if ($KhongSecureBoot) { $a += '/NOSB' }
    return , $a
}

function Find-IsoFiles {
    # File .iso trên USB (trả từng file, gọi bằng @(...); bỏ thư mục AutoSetup, ventoy); Loai 'windows' khi tên khớp ventoy.locTenIso (được menu cài tự động).
    param([string]$Root, [string]$Pattern)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return }
    $skip = @((Join-Path $Root 'AutoSetup'), (Join-Path $Root 'ventoy'))
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $full = $f.FullName
        if (@($skip | Where-Object { $full.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
        $loai = if ($f.Name -match $Pattern) { 'windows' } elseif ($f.Name -match $script:RescueIso) { 'cuu-ho' } else { 'khac' }
        $chu = @{ 'windows' = 'Windows: có menu cài tự động'; 'cuu-ho' = 'Cứu hộ (Mini Windows, công cụ)'; 'khac' = 'Khởi động bằng Ventoy' }
        [pscustomobject]@{ Ten = $full.Substring($Root.TrimEnd('\').Length + 1); DuongDan = $full; KichThuocChu = Format-Size $f.Length
            Loai = $loai; LoaiChu = $chu[$loai] }
    }
}

function Set-ConfigPath {
    # Đặt giá trị theo đường dẫn 'a.b.c' trong một PSCustomObject (tạo đối tượng con nếu thiếu). Trả lại đối tượng.
    param($Object, [string]$Path, $Value)
    if ($null -eq $Object) { $Object = [pscustomobject]@{} }
    $parts = $Path.Split('.')
    $cur = $Object
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $p = $cur.PSObject.Properties[$parts[$i]]
        if (-not $p -or -not ($p.Value -is [Management.Automation.PSCustomObject])) {
            $cur | Add-Member -NotePropertyName $parts[$i] -NotePropertyValue ([pscustomobject]@{}) -Force
            $p = $cur.PSObject.Properties[$parts[$i]]
        }
        $cur = $p.Value
    }
    $cur | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $Value -Force
    return $Object
}

function Set-AppSelection {
    # Bản sao danh sách ứng dụng (UngDung.json) với macDinh theo $Chon (danh sách khoá được chọn).
    param($AppList, [string[]]$Chon)
    $copy = (ConvertTo-JsonText $AppList) | ConvertFrom-Json
    foreach ($a in @($copy.ungDung)) { $a | Add-Member -NotePropertyName macDinh -NotePropertyValue ([string]$a.khoa -in $Chon) -Force }
    return $copy
}
