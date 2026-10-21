<#
  Giao diện tạo USB (thẻ "doc-may": đọc ổ đĩa máy thật, không ghi gì lên ổ nào ngoài thư mục tạm):
  hàm nhận USB, Ventoy, ISO, cấu hình; việc nền chép ISO; từ chối cài Ventoy lên ổ không phải USB; nạp giao diện, lưu
  cấu hình, bấm Tạo USB vào thư mục giả làm USB; dựng ảnh cửa sổ.
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')
$env:AUTOSETUP_GITHUB_API = 'http://127.0.0.1:9'   # không ra mạng: Install-VentoyTool phải dùng bản đã tải
. (Join-Path $script:Repo 'scripts\lib\USB.ps1')
$nen = Join-Path $script:Repo 'scripts\ViecNenUSB.ps1'
$gui = Join-Path $script:Repo 'scripts\GiaoDienUSB.ps1'

$d = New-TestDir 'giaodien'
try {
    # ---- nhận USB
    $inv = [pscustomobject]@{
        Disks      = @(
            [pscustomobject]@{ Number = 0; BusType = 'NVMe'; FriendlyName = 'SSD trong'; Size = 256GB; IsBoot = $true; IsSystem = $true }
            [pscustomobject]@{ Number = 1; BusType = 'SATA'; FriendlyName = 'HDD trong'; Size = 1TB; IsBoot = $false; IsSystem = $false }
            [pscustomobject]@{ Number = 2; BusType = 'USB'; FriendlyName = 'SanDisk Ultra '; Size = 64GB; IsBoot = $false; IsSystem = $false }
            [pscustomobject]@{ Number = 3; BusType = 'USB'; FriendlyName = 'Kingston'; Size = 32GB; IsBoot = $false; IsSystem = $false }
            [pscustomobject]@{ Number = 4; BusType = 'USB'; FriendlyName = 'Ổ USB khởi động'; Size = 32GB; IsBoot = $true; IsSystem = $false }
        )
        Partitions = @(
            [pscustomobject]@{ DiskNumber = 2; PartitionNumber = 1; DriveLetter = 'E'; Label = 'Ventoy'; Size = 63GB; Free = 40GB }
            [pscustomobject]@{ DiskNumber = 2; PartitionNumber = 2; DriveLetter = ''; Label = 'VTOYEFI'; Size = 32MB; Free = 1MB }
            [pscustomobject]@{ DiskNumber = 3; PartitionNumber = 1; DriveLetter = 'F'; Label = 'DATA'; Size = 32GB; Free = 30GB }
        )
    }
    $usbs = ConvertTo-UsbDiskList $inv
    Assert-Equal '2,3' (($usbs | ForEach-Object { $_.So }) -join ',') 'chỉ lấy USB, bỏ ổ trong và ổ khởi động'
    Assert-True ($usbs[0].Ventoy -and $usbs[0].ODuLieu -eq 'E:\') 'USB có VTOYEFI: nhận Ventoy, ổ dữ liệu E:\'
    Assert-Equal 'SanDisk Ultra' $usbs[0].Ten 'bỏ dấu cách thừa trong tên'
    Assert-True (-not $usbs[1].Ventoy) 'USB thường: chưa có Ventoy'
    Assert-Equal 0 @(ConvertTo-UsbDiskList ([pscustomobject]@{ Disks = @(); Partitions = @() })).Count 'không có USB: danh sách rỗng'

    # ---- Ventoy: mã băm, chọn gói, tham số
    $hex = 'ee3917bd5a9973c0b2f8f3ef85048bf68ae089ec88f5561ad78b6ad308b51ab5'
    Assert-Equal $hex (Get-ShaFromDigest "sha256:$($hex.ToUpper())") 'mã băm GitHub sha256:...'
    Assert-Equal '' (Get-ShaFromDigest 'md5:abc') 'mã băm không phải sha256: trống'
    $list = "aaaa  x`n$hex  ventoy-1.1.18-livecd.iso`n082c478e8c432e1ac653899fcf50e3a4077a2851bc6112b5ddd305459621 64a9  ventoy-1.1.18-windows.zip`n"
    Assert-Equal $hex (Get-ShaFromList $list 'ventoy-1.1.18-livecd.iso') 'sha256.txt: đúng dòng của tệp'
    Assert-Equal '' (Get-ShaFromList $list 'ventoy-1.1.18-windows.zip') 'sha256.txt: dòng hỏng thì trống'
    $rel = [pscustomobject]@{ assets = @(
            [pscustomobject]@{ name = 'ventoy-1.1.18-linux.tar.gz'; browser_download_url = 'u1'; digest = '' }
            [pscustomobject]@{ name = 'ventoy-1.1.18-windows.zip'; browser_download_url = 'u2'; digest = "sha256:$hex" }
            [pscustomobject]@{ name = 'sha256.txt'; browser_download_url = 'u3'; digest = '' }) }
    $a = Select-VentoyAsset $rel
    Assert-True ($a.PhienBan -eq '1.1.18' -and $a.Url -eq 'u2' -and $a.Sha256 -eq $hex -and $a.Sha256Url -eq 'u3') 'chọn gói Windows của bản phát hành'
    Assert-True ($null -eq (Select-VentoyAsset ([pscustomobject]@{ assets = @() }))) 'không có gói Windows: $null'
    Assert-Equal 'VTOYCLI /I /PhyDrive:2 /GPT' ((Get-Ventoy2DiskArgs -Lenh I -So 2 -Gpt) -join ' ') 'tham số cài mới GPT'
    Assert-Equal 'VTOYCLI /U /PhyDrive:3 /NOSB' ((Get-Ventoy2DiskArgs -Lenh U -So 3 -Gpt -KhongSecureBoot) -join ' ') 'cập nhật: bỏ /GPT, có /NOSB'

    $cache = Join-Path $d 'ventoy-cache'
    try { [void](Install-VentoyTool -CacheDir $cache -Log { }); $ok = $false } catch { $ok = $_.Exception.Message -match 'Không tải được Ventoy' }
    Assert-True $ok 'không mạng, chưa tải bao giờ: báo lỗi rõ'
    foreach ($v in '1.1.9', '1.1.18') { New-Item -ItemType Directory -Path (Join-Path $cache "ventoy-$v") -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $cache "ventoy-$v\Ventoy2Disk.exe"), '') }
    Assert-True ((Find-CachedVentoy $cache) -like '*ventoy-1.1.18\Ventoy2Disk.exe') 'bản đã tải mới nhất theo số phiên bản (1.1.18 hơn 1.1.9)'
    Assert-True ((Install-VentoyTool -CacheDir $cache -Log { }) -like '*ventoy-1.1.18\Ventoy2Disk.exe') 'không mạng: dùng bản đã tải'

    # ---- tải Ventoy trọn đường (GitHub giả bằng file://): tải, kiểm SHA-256, giải nén
    $gh = Join-Path $d 'github'
    $pkg = Join-Path $d 'goi\ventoy-9.9.9'
    New-Item -ItemType Directory -Path (Join-Path $pkg 'altexe'), (Join-Path $gh 'repos\ventoy\Ventoy\releases'), (Join-Path $gh 'tai') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $pkg 'Ventoy2Disk.exe'), 'gia'); [IO.File]::WriteAllText((Join-Path $pkg 'altexe\Ventoy2Disk_X64.exe'), 'gia')
    $zip = Join-Path $gh 'tai\ventoy-9.9.9-windows.zip'
    Compress-Archive -Path $pkg -DestinationPath $zip
    $zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $gh 'tai\sha256.txt'), "$zipHash  ventoy-9.9.9-windows.zip`n")
    $setRelease = {
        param($digest)
        $json = '{{"tag_name":"v9.9.9","assets":[{{"name":"ventoy-9.9.9-windows.zip","browser_download_url":"{0}","digest":"{1}"}},{{"name":"sha256.txt","browser_download_url":"{2}","digest":""}}]}}' -f ([Uri]$zip).AbsoluteUri, $digest, ([Uri](Join-Path $gh 'tai\sha256.txt')).AbsoluteUri
        [IO.File]::WriteAllText((Join-Path $gh 'repos\ventoy\Ventoy\releases\latest'), $json)
    }
    $script:VentoyApi = ([Uri]$gh).AbsoluteUri.TrimEnd('/')
    & $setRelease "sha256:$zipHash"
    $c1 = Join-Path $d 'cache-tai'
    $logs = New-Object System.Collections.Generic.List[string]
    $exe = Install-VentoyTool -CacheDir $c1 -Log { param($t) $logs.Add($t) }
    Assert-Equal (Join-Path $c1 'ventoy-9.9.9\Ventoy2Disk.exe') $exe 'tải Ventoy: giải nén đúng chỗ (gói có thư mục ventoy-<phiên bản>)'
    Assert-True (Test-Path (Join-Path $c1 'ventoy-9.9.9\altexe\Ventoy2Disk_X64.exe')) 'tải Ventoy: đủ thư mục con'
    Assert-Equal 'ventoy-9.9.9' ((Get-ChildItem $c1 -Force | ForEach-Object Name) -join ',') 'tải Ventoy: không để file tạm, thư mục giải nén dở'
    Assert-True (($logs -join ' ') -match 'mã băm SHA-256 khớp') 'tải Ventoy: báo mã băm khớp'
    $logs.Clear(); [void](Install-VentoyTool -CacheDir $c1 -Log { param($t) $logs.Add($t) })
    Assert-True (($logs -join ' ') -match 'đã tải từ trước') 'tải lại: dùng bản đã tải, không tải nữa'
    & $setRelease ''
    Assert-True ((Install-VentoyTool -CacheDir (Join-Path $d 'cache-sha') -Log { }) -like '*ventoy-9.9.9\Ventoy2Disk.exe') 'GitHub không ghi mã băm: dùng sha256.txt'
    & $setRelease ('sha256:' + ('0' * 64))
    $c3 = Join-Path $d 'cache-sai'
    try { [void](Install-VentoyTool -CacheDir $c3 -Log { }); $ok = $false } catch { $ok = $_.Exception.Message -match 'sai mã băm' }
    Assert-True $ok 'sai mã băm: không dùng gói tải về'
    Assert-Equal '' ((Get-ChildItem $c3 -Force -ErrorAction SilentlyContinue | ForEach-Object Name) -join ',') 'sai mã băm: không giải nén, không để file tạm'
    $script:VentoyApi = $env:AUTOSETUP_GITHUB_API

    # ---- ISO, cấu hình
    $usb = Join-Path $d 'usb'
    New-Item -ItemType Directory -Path (Join-Path $usb 'ISO'), (Join-Path $usb 'AutoSetup'), (Join-Path $usb 'ventoy') -Force | Out-Null
    foreach ($f in 'Win11_24H2_x64.iso', 'ISO\Anhdv_Boot_Free_26.4.0.iso', 'ISO\ubuntu-24.04.iso', 'AutoSetup\x.iso') { [IO.File]::WriteAllText((Join-Path $usb $f), 'iso') }
    $isos = Find-IsoFiles $usb '(?i)win(dows)?[ ._-]*1[01]'
    Assert-Equal 'ISO\Anhdv_Boot_Free_26.4.0.iso|ISO\ubuntu-24.04.iso|Win11_24H2_x64.iso' (($isos | ForEach-Object { $_.Ten }) -join '|') 'ISO trên USB (bỏ thư mục AutoSetup)'
    Assert-Equal 'cuu-ho,khac,windows' (($isos | ForEach-Object { $_.Loai }) -join ',') 'loại ISO: cứu hộ, khác, Windows'
    Assert-Equal 0 @(Find-IsoFiles (Join-Path $d 'khong-co') 'x').Count 'thư mục không có: rỗng'
    $o = Set-ConfigPath $null 'taiKhoan.ten' 'KeToan'
    $o = Set-ConfigPath $o 'taiKhoan.cheDo' 'tu-dong'
    $o = Set-ConfigPath $o 'tenMay' 'hoi'
    Assert-True ($o.taiKhoan.ten -eq 'KeToan' -and $o.taiKhoan.cheDo -eq 'tu-dong' -and $o.tenMay -eq 'hoi') 'Set-ConfigPath tạo khoá lồng nhau'
    $apps = Read-JsonFile (Join-Path $script:Repo 'cau-hinh\UngDung.json')
    $sel = Set-AppSelection $apps @('Zalo', 'Chrome')
    Assert-Equal 'Zalo,Chrome' ((@($sel.ungDung | Where-Object { $_.macDinh }) | ForEach-Object { $_.khoa }) -join ',') 'chọn ứng dụng theo khoá'
    Assert-True (@($apps.ungDung | Where-Object { $_.khoa -eq 'EVKey' })[0].macDinh) 'Set-AppSelection không sửa bản gốc'

    # ---- việc nền: chép ISO
    $src = Join-Path $d 'nguon'
    New-Item -ItemType Directory -Path $src, (Join-Path $d 'dich') -Force | Out-Null
    $bytes = New-Object byte[] (6MB); (New-Object Random 7).NextBytes($bytes)
    [IO.File]::WriteAllBytes((Join-Path $src 'a b.iso'), $bytes); [IO.File]::WriteAllText((Join-Path $src 'c.iso'), 'nho')
    $r = Invoke-Ps $nen @('-Viec', 'chep', '-Nguon', ((Join-Path $src 'a b.iso') + '|' + (Join-Path $src 'c.iso')), '-Dich', (Join-Path $d 'dich'))
    Assert-Equal 0 $r.Code "chép ISO: mã 0 $(if ($r.Code) { $r.Text })"
    Assert-True ($r.Text -match '##TIENDO 100') 'chép ISO: báo tiến độ 100'
    Assert-Equal (Get-FileHash (Join-Path $src 'a b.iso')).Hash (Get-FileHash (Join-Path $d 'dich\a b.iso')).Hash 'chép ISO: nội dung đúng'
    Assert-Equal 0 @(Get-ChildItem (Join-Path $d 'dich') -Filter '*.dang-chep').Count 'chép ISO: không để file tạm'
    $r = Invoke-Ps $nen @('-Viec', 'chep', '-Nguon', (Join-Path $src 'a b.iso'), '-Dich', (Join-Path $d 'dich'))
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'Bỏ qua a b\.iso') 'chép lại: bỏ qua file đã có cùng kích thước'

    # ---- việc nền: không cài Ventoy lên ổ trong
    $inner = @(Get-Disk | Where-Object { $_.IsBoot -or $_.IsSystem }) | Select-Object -First 1
    if ($inner) {
        $r = Invoke-Ps $nen @('-Viec', 'ventoy', '-Lenh', 'I', '-So', [string]$inner.Number, '-CacheDir', (Join-Path $d 'khong-tai'))
        Assert-True ($r.Code -eq 1 -and $r.Text -match 'không phải USB, không ghi') "từ chối cài Ventoy lên ổ hệ thống (số $($inner.Number))"
        Assert-True (-not (Test-Path (Join-Path $d 'khong-tai'))) 'từ chối trước khi tải Ventoy'
    }

    # ---- giao diện: nạp, lưu cấu hình, Tạo USB
    $env:AUTOSETUP_OUT = Join-Path $d 'out'
    $env:AUTOSETUP_CAUHINH = Join-Path $d 'cau-hinh'
    New-Item -ItemType Directory -Path $env:AUTOSETUP_CAUHINH -Force | Out-Null
    foreach ($f in 'CauHinh.json', 'UngDung.json', 'Office.xml') { Copy-Item (Join-Path $script:Repo "cau-hinh\$f") $env:AUTOSETUP_CAUHINH }
    . $gui -ChiNap -KhongNangQuyen -O $usb
    $script:TuTraLoi = 'Yes'
    Assert-Equal 0 @($ui.Keys | Where-Object { $null -eq $ui[$_] }).Count 'mọi x:Name trong XAML tìm thấy'
    $used = @([regex]::Matches([IO.File]::ReadAllText($gui), '\$ui\.(\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Assert-Equal '' (@($used | Where-Object { -not $ui.ContainsKey($_) }) -join ',') 'mọi $ui.<tên> dùng trong script có trong XAML'
    Assert-Equal $usb $script:Root 'nhận USB đích từ -O'
    Assert-Equal 3 @($ui.lvIso.ItemsSource).Count 'thẻ ISO liệt kê 3 ISO'
    Assert-Equal 'bios' (Get-ComboTag $ui.cboBanQuyen) 'nạp cấu hình: key theo BIOS'
    Assert-True (-not $ui.txtTen.IsEnabled) 'tài khoản hỏi khi cài: ô tên tắt'

    Select-ComboTag $ui.cboTaiKhoan 'tu-dong'
    Update-FormState
    Assert-True $ui.txtTen.IsEnabled 'tài khoản tự tạo: ô tên bật'
    $ui.txtTen.Text = 'Administrator'
    Assert-True (-not (Save-ConfigForm)) 'tên tài khoản cấm: không lưu'
    Assert-True (-not (Test-Path (Join-Path $env:AUTOSETUP_CAUHINH 'CauHinh.local.json'))) 'tên cấm: chưa có CauHinh.local.json'
    $ui.txtTen.Text = 'KeToan'
    $ui.txtTenHienThi.Text = 'Kế toán'
    $ui.pwdMatKhau.Password = 'Thu-GiaoDien-7'
    $ui.rbTenHoi.IsChecked = $true
    $ui.txtDungLuongC.Text = '120'
    foreach ($cb in $ui.lbUngDung.Items) { $cb.IsChecked = [string]$cb.Tag -in 'Zalo', 'EVKey' }
    Assert-True (Save-ConfigForm) 'lưu cấu hình hợp lệ'
    $loc = Read-JsonFile (Join-Path $env:AUTOSETUP_CAUHINH 'CauHinh.local.json')
    Assert-True ($loc.taiKhoan.cheDo -eq 'tu-dong' -and $loc.taiKhoan.ten -eq 'KeToan' -and $loc.tenMay -eq 'hoi' -and $loc.oDia.dungLuongC_GB -eq 120) 'CauHinh.local.json có giá trị trên giao diện'
    Assert-True ([IO.File]::ReadAllText((Join-Path $env:AUTOSETUP_CAUHINH 'CauHinh.local.json')) -notmatch 'Thu-GiaoDien-7') 'mật khẩu không ghi vào cấu hình'
    $ua = Read-JsonFile (Join-Path $env:AUTOSETUP_CAUHINH 'UngDung.local.json')
    Assert-Equal 'Zalo,EVKey' ((@($ua.ungDung | Where-Object { $_.macDinh }) | ForEach-Object { $_.khoa }) -join ',') 'UngDung.local.json theo ô đã chọn'

    $ui.cbChayThu.IsChecked = $false
    Start-Create
    $pw = @($script:Job.Temp | Where-Object { $_ -like '*AutoSetup-mk-*' })
    Assert-Equal 1 $pw.Count 'Tạo USB: truyền mật khẩu qua file tạm'
    $deadline = (Get-Date).AddMinutes(3)
    while ($script:Job -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300; Receive-Background }
    $log = $ui.txtNhatKy.Text
    Assert-True (-not $script:Job) 'Tạo USB: việc nền xong trong 3 phút'
    Assert-True ($log -match 'Đã chép AutoSetup') "Tạo USB: nhật ký có 'Đã chép AutoSetup'"
    Assert-True ($ui.txtTrangThai.Text -match 'xong') "Tạo USB: trạng thái xong ($($ui.txtTrangThai.Text))"
    Assert-True (-not (Test-Path -LiteralPath $pw[0])) 'Tạo USB: xoá file mật khẩu tạm'
    Assert-Equal 6 @(Get-ChildItem (Join-Path $usb 'AutoSetup\unattend') -Filter '*.xml').Count 'Tạo USB: 6 file unattend trên USB'
    $vj = Read-JsonFile (Join-Path $usb 'ventoy\ventoy.json')
    Assert-Equal '/Win11_24H2_x64.iso' (@($vj.auto_install)[0].image) 'Tạo USB: ventoy.json có menu cho ISO Windows'
    Assert-Equal 1 @($vj.auto_install).Count 'Tạo USB: không thêm menu cho ISO cứu hộ, Linux'
    $x1 = [IO.File]::ReadAllText((Join-Path $usb 'AutoSetup\unattend\1_Chon-o-bang-tay.xml'))
    Assert-True ($x1 -match 'KeToan') 'Tạo USB: unattend có tài khoản KeToan'
    Assert-True ($log -notmatch 'Thu-GiaoDien-7') 'Tạo USB: nhật ký không lộ mật khẩu'
    $ucfg = Read-JsonFile (Join-Path $usb 'AutoSetup\cau-hinh\UngDung.json')
    Assert-Equal 'Zalo,EVKey' ((@($ucfg.ungDung | Where-Object { $_.macDinh }) | ForEach-Object { $_.khoa }) -join ',') 'Tạo USB: USB có danh sách ứng dụng đã chọn'

    # ---- ảnh cửa sổ
    $png = Join-Path $d 'the3.png'
    $r = Invoke-Ps $gui @('-AnhRa', $png, '-The', '3', '-O', $usb)
    Assert-True ($r.Code -eq 0 -and (Test-Path $png) -and (Get-Item $png).Length -gt 10KB) 'dựng ảnh cửa sổ (-AnhRa)'
} finally {
    Remove-Item Env:\AUTOSETUP_OUT, Env:\AUTOSETUP_CAUHINH, Env:\AUTOSETUP_GITHUB_API -ErrorAction SilentlyContinue
    Remove-TestDir $d
}
Complete-Test
