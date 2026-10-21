<#
  Việc chạy nền cho giao diện tạo USB (GiaoDienUSB.ps1 chạy script này trong tiến trình riêng, đọc đầu ra từng dòng).
  Dòng "##TIENDO <0-100>" là phần trăm tiến độ, dòng khác là nhật ký.
    -Viec ventoy -Lenh I|U -So <số ổ> [-KichThuoc <byte>] [-Ten <tên ổ>] [-Gpt] [-KhongSecureBoot] [-CacheDir <thư mục>]
        tải Ventoy (kiểm SHA-256) rồi chạy Ventoy2Disk: I = cài mới (XOÁ SẠCH USB), U = cập nhật (giữ dữ liệu).
        -KichThuoc, -Ten: ổ người dùng đã thấy trong danh sách; ổ số -So khác đi (rút USB, cắm cái khác) thì không ghi.
    -Viec chep -Nguon <file1|file2...> -Dich <thư mục>
        chép file (ISO) lên USB, bỏ qua file đã có cùng kích thước
  Mã thoát: 0 xong, 1 lỗi.
#>
param(
    [ValidateSet('ventoy', 'chep')][string]$Viec,
    [ValidateSet('I', 'U')][string]$Lenh = 'U',
    [int]$So = -1,
    [double]$KichThuoc = 0,
    [string]$Ten = '',
    [switch]$Gpt,
    [switch]$KhongSecureBoot,
    [string]$CacheDir = '',
    [string]$Nguon = '',
    [string]$Dich = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\USB.ps1')

function Write-Progress2 { param([int]$Pct) [Console]::Out.WriteLine("##TIENDO $Pct"); [Console]::Out.Flush() }
function Write-Log { param([string]$Text) [Console]::Out.WriteLine($Text); [Console]::Out.Flush() }

function Invoke-Ventoy {
    if ($So -lt 0) { throw 'Thiếu số ổ (-So).' }
    # Kiểm lại ổ ngay trước khi ghi: chỉ USB/thẻ nhớ, không phải ổ khởi động, ổ hệ thống (Ventoy2Disk cũng tự từ chối
    # ổ không phải USB vì không truyền /NOUSBCheck).
    $d = Get-Disk -Number $So
    if ([string]$d.BusType -notin 'USB', 'SD', 'MMC' -or $d.IsBoot -or $d.IsSystem) { throw "Ổ số $So ($($d.FriendlyName), bus $($d.BusType)) không phải USB, không ghi." }
    if (($KichThuoc -and [double]$d.Size -ne $KichThuoc) -or ($Ten -and ([string]$d.FriendlyName).Trim() -ne $Ten.Trim())) {
        throw "Ổ số $So bây giờ là $(([string]$d.FriendlyName).Trim()) ($(Format-Size $d.Size)), không phải ổ đã chọn: bấm Làm mới rồi chọn lại."
    }
    if (-not $CacheDir) { $CacheDir = Join-Path $repo 'out\ventoy' }
    $exe = Install-VentoyTool -CacheDir $CacheDir -Log { param($t) Write-Log $t }
    $dir = Split-Path -Parent $exe
    foreach ($f in 'cli_done.txt', 'cli_percent.txt', 'cli_log.txt') { Remove-Item -LiteralPath (Join-Path $dir $f) -Force -ErrorAction SilentlyContinue }
    $a = Get-Ventoy2DiskArgs -Lenh $Lenh -So $So -Gpt:$Gpt -KhongSecureBoot:$KhongSecureBoot
    Write-Log ("{0} Ventoy trên ổ số {1}: {2} ({3})..." -f $(if ($Lenh -eq 'I') { 'Cài' } else { 'Cập nhật' }), $So, $d.FriendlyName, (Format-Size $d.Size))
    $p = Start-Process -FilePath $exe -ArgumentList $a -WorkingDirectory $dir -PassThru -WindowStyle Hidden
    $last = -1
    $done = Join-Path $dir 'cli_done.txt'
    while ($true) {
        Start-Sleep -Milliseconds 500
        $pct = try { [int]([IO.File]::ReadAllText((Join-Path $dir 'cli_percent.txt')).Trim()) } catch { -1 }
        if ($pct -ge 0 -and $pct -ne $last) { Write-Progress2 $pct; $last = $pct }
        if (Test-Path -LiteralPath $done) { Start-Sleep -Milliseconds 300; break }
        if ($p.HasExited) {
            # Đợi thêm tối đa 5 giây phòng cli_done.txt ghi chậm hơn lúc tiến trình thoát.
            for ($i = 0; $i -lt 10 -and -not (Test-Path -LiteralPath $done); $i++) { Start-Sleep -Milliseconds 500 }
            break
        }
    }
    $code = if (Test-Path -LiteralPath $done) { ([IO.File]::ReadAllText($done)).Trim() } else { '' }
    if ($code -eq '0') { Write-Progress2 100; Write-Log 'Ventoy2Disk báo xong.'; return }
    $log = Join-Path $dir 'cli_log.txt'
    if (Test-Path -LiteralPath $log) { Write-Log '--- cuối nhật ký Ventoy2Disk ---'; Get-Content -LiteralPath $log -Tail 15 | ForEach-Object { Write-Log $_ } }
    throw $(if ($code) { 'Ventoy2Disk báo lỗi (cli_done.txt = 1).' } else { 'Ventoy2Disk thoát mà không báo xong.' })
}

function Invoke-Copy {
    $files = @($Nguon -split '\|' | Where-Object { $_ })
    if (-not $files.Count -or -not $Dich) { throw 'Thiếu -Nguon hoặc -Dich.' }
    if (-not (Test-Path -LiteralPath $Dich)) { throw "Không thấy $Dich" }
    $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Dich).Path)
    $drive = New-Object IO.DriveInfo $root
    $items = foreach ($f in $files) {
        $src = Get-Item -LiteralPath $f
        $dst = Join-Path $Dich $src.Name
        $skip = (Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).Length -eq $src.Length)
        [pscustomobject]@{ Src = $src; Dst = $dst; Skip = $skip }
    }
    $need = ($items | Where-Object { -not $_.Skip } | ForEach-Object { $_.Src.Length } | Measure-Object -Sum).Sum
    if ($need -gt $drive.AvailableFreeSpace) { throw ("USB không đủ chỗ: cần {0}, còn {1}." -f (Format-Size $need), (Format-Size $drive.AvailableFreeSpace)) }
    if ($drive.DriveFormat -eq 'FAT32' -and @($items | Where-Object { -not $_.Skip -and $_.Src.Length -ge 4GB }).Count) { throw 'USB định dạng FAT32 không chứa được file từ 4 GB trở lên (Ventoy mặc định exFAT).' }
    $total = [math]::Max(1, $need); $doneBytes = 0; $last = -1
    $buf = New-Object byte[] (4MB)
    foreach ($it in $items) {
        if ($it.Skip) { Write-Log "Bỏ qua $($it.Src.Name): đã có trên USB, cùng kích thước."; continue }
        Write-Log ("Chép {0} ({1})..." -f $it.Src.Name, (Format-Size $it.Src.Length))
        $tmp = "$($it.Dst).dang-chep"
        $in = [IO.File]::OpenRead($it.Src.FullName)
        try {
            $out = [IO.File]::Create($tmp)
            try {
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n); $doneBytes += $n
                    $pct = [int](100 * $doneBytes / $total)
                    if ($pct -ne $last) { Write-Progress2 $pct; $last = $pct }
                }
            } finally { $out.Dispose() }
        } finally { $in.Dispose() }
        Move-Item -LiteralPath $tmp -Destination $it.Dst -Force
        Write-Log "  xong $($it.Src.Name)"
    }
    Write-Progress2 100
}

try {
    switch ($Viec) {
        'ventoy' { Invoke-Ventoy }
        'chep' { Invoke-Copy }
    }
    exit 0
} catch {
    Write-Log "[X] $($_.Exception.Message)"
    exit 1
}
