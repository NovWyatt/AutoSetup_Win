<#
  Bước sau cài: chọn ứng dụng theo nhóm, cài bằng winget giả (đã có, cài được, cài lỗi, thư mục cài riêng, lối tắt
  cho ứng dụng portable), trạng
  thái đọc ghi lại được, đổi tên máy, rồi chạy thử cả lượt (-ChayThu) trên bản sao trong thư mục tạm.
  KiemThu: doc-may (lượt chạy thử đọc ổ đĩa, thiết bị của máy thật, không đổi gì)
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')

$d = New-TestDir 'saucai'
try {
    $env:AUTOSETUP_GOC = Join-Path $d 'goc'
    New-Item -ItemType Directory -Path $env:AUTOSETUP_GOC -Force | Out-Null
    # winget giả: list theo file đánh dấu, install tạo file đánh dấu (id có chữ Loi thì lỗi 1603), ghi lại lệnh.
    $fake = Join-Path $d 'wg'
    New-Item -ItemType Directory -Path $fake -Force | Out-Null
    $cmd = @(
        '@echo off',
        'if /i "%~1"=="--version" (echo v1.99.0& exit /b 0)',
        'if /i "%~1"=="source" exit /b 0',
        'if /i "%~1"=="list" goto list',
        'if /i "%~1"=="install" goto install',
        'exit /b 0',
        ':list',
        'if exist "%AS_FAKE%\%~3.ok" exit /b 0',
        'exit /b -1978335212',
        ':install',
        'echo %*>>"%AS_FAKE%\install.log"',
        'echo %~3| findstr /i "Loi" >nul && exit /b 1603',
        'echo %~3| findstr /i "Treo" >nul && (ping -n 31 127.0.0.1 >nul& exit /b 0)',
        'type nul > "%AS_FAKE%\%~3.ok"',
        'exit /b 0'
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $fake 'winget.cmd'), $cmd + "`r`n", [Text.Encoding]::ASCII)
    $env:AS_FAKE = $fake
    $env:AUTOSETUP_WINGET = Join-Path $fake 'winget.cmd'

    $env:AUTOSETUP_TEST_NAP = '1'
    . (Join-Path $script:Repo 'sau-cai\SauCai.ps1')
    $env:AUTOSETUP_TEST_NAP = ''

    # ---- chọn ứng dụng
    $apps = Read-AppList (Join-Path $script:Repo 'cau-hinh\UngDung.json')
    $sel = Select-Apps $apps
    Assert-Equal (@($apps | Where-Object { $_.macDinh }).Count) $sel.Chon.Count 'chọn đúng các ứng dụng macDinh'
    $synthetic = @(
        [pscustomobject]@{ khoa = 'A'; id = 'X.A'; ten = 'A'; macDinh = $true; nhom = 'g' },
        [pscustomobject]@{ khoa = 'B'; id = 'X.B'; ten = 'B'; macDinh = $true; nhom = 'g' },
        [pscustomobject]@{ khoa = 'C'; id = 'X.C'; ten = 'C'; macDinh = $false },
        [pscustomobject]@{ khoa = 'D'; id = 'X.D'; ten = 'D'; macDinh = $true }
    )
    $sel = Select-Apps $synthetic
    Assert-Equal 'A,D' (($sel.Chon | ForEach-Object { $_.khoa }) -join ',') 'cùng nhóm chỉ lấy cái đứng trước, bỏ macDinh false'
    Assert-Equal 'B' (($sel.BoQua | ForEach-Object { $_.App.khoa }) -join ',') 'báo bỏ qua ứng dụng cùng nhóm'

    # ---- winget giả
    $w = Initialize-Winget -WaitSeconds 5
    Assert-True $w.Ok "Initialize-Winget với winget giả: $($w.GhiChu)"
    [IO.File]::WriteAllText((Join-Path $fake 'Co.San.ok'), '')
    $list = @(
        [pscustomobject]@{ khoa = 'CoSan'; id = 'Co.San'; ten = 'Có sẵn'; macDinh = $true },
        [pscustomobject]@{ khoa = 'Moi'; id = 'Ung.Moi'; ten = 'Mới'; macDinh = $true; doiThuMuc = $true },
        [pscustomobject]@{ khoa = 'Hong'; id = 'App.Loi'; ten = 'Hỏng'; macDinh = $true }
    )
    $res = Install-Apps -Apps $list -InstallRoot 'D:\Program Files'
    Assert-Equal 'da-co' $res[0].ketQua 'ứng dụng có sẵn: bỏ qua'
    Assert-Equal 'da-cai' $res[1].ketQua 'ứng dụng mới: cài xong (đọc lại danh sách đã cài)'
    Assert-Equal 'loi' $res[2].ketQua 'ứng dụng cài lỗi: báo lỗi'
    Assert-Equal 1603 $res[2].ma 'giữ mã lỗi của bộ cài'
    $log = @(Get-Content (Join-Path $fake 'install.log'))
    Assert-Equal 3 $log.Count 'cài mới 1 lần, cài lỗi thử lại 1 lần'
    Assert-True ($log[0] -match '--location "D:\\Program Files\\Moi"') 'doiThuMuc: truyền --location'
    Assert-True ($log[0] -match '--source winget' -and $log[0] -match '--silent') 'chỉ dùng nguồn winget, cài im lặng'
    Assert-True ($log[1] -notmatch '--location') 'không doiThuMuc: không truyền --location'
    $dry = Install-Apps -Apps @([pscustomobject]@{ khoa = 'Z'; id = 'Z.Z'; ten = 'Z'; macDinh = $true }) -DryRun
    Assert-Equal 'chay-thu' $dry[0].ketQua 'chạy thử: không cài'
    Assert-True (-not (Test-Path (Join-Path $fake 'Z.Z.ok'))) 'chạy thử: winget install không được gọi'

    # ---- ứng dụng portable: lối tắt trong Start, Startup
    $env:AUTOSETUP_PORTABLE = Join-Path $d 'portable'
    $env:AUTOSETUP_LOITAT = Join-Path $d 'loitat'
    $pk = Join-Path $env:AUTOSETUP_PORTABLE 'Bo.Go_Microsoft.Winget.Source_8wekyb3d8bbwe\x64'
    New-Item -ItemType Directory -Path $pk -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $pk 'BoGo.exe'), '')
    $port = @(
        [pscustomobject]@{ khoa = 'BoGo'; id = 'Bo.Go'; ten = 'Bộ gõ'; macDinh = $true; loiTat = 'BoGo.exe'; tuChay = $true },
        [pscustomobject]@{ khoa = 'Thieu'; id = 'Thieu.Exe'; ten = 'Thiếu'; macDinh = $true; loiTat = 'Thieu.exe' }
    )
    $res = Install-Apps -Apps $port
    $lnk = Join-Path $env:AUTOSETUP_LOITAT 'Programs\BoGo.lnk'
    Assert-Equal 'da-cai' $res[0].ketQua 'portable: cài xong'
    Assert-True (Test-Path $lnk) 'portable: có lối tắt trong Start'
    Assert-True (Test-Path (Join-Path $env:AUTOSETUP_LOITAT 'Startup\BoGo.lnk')) 'tuChay: có lối tắt trong Startup'
    Assert-Equal (Join-Path $pk 'BoGo.exe') ((New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath) 'lối tắt trỏ đúng file chạy'
    Assert-True ($res[1].ghiChu -match 'không thấy Thieu\.exe') 'không thấy file chạy: ghi chú, không lỗi cả bước'
    Assert-True (-not (Test-Path (Join-Path $env:AUTOSETUP_LOITAT 'Startup\Thieu.lnk'))) 'không tuChay: không vào Startup'
    Remove-Item -LiteralPath $lnk
    $res = Install-Apps -Apps @($port[0])
    Assert-True ($res[0].ketQua -eq 'da-co' -and (Test-Path $lnk)) 'đã có: vẫn bảo đảm lối tắt'

    # ---- bộ cài treo: dừng khi quá giờ (cả tiến trình con), không thử lại
    $t0 = Get-Date
    $res = Install-Apps -Apps @([pscustomobject]@{ khoa = 'Treo'; id = 'App.Treo'; ten = 'Treo'; macDinh = $true }) -TimeoutSeconds 3
    $sec = [int]((Get-Date) - $t0).TotalSeconds
    Assert-Equal 'loi' $res[0].ketQua 'bộ cài treo: báo lỗi'
    Assert-True ($res[0].ghiChu -match 'quá 3 giây') "bộ cài treo: ghi chú quá giờ ($($res[0].ghiChu))"
    Assert-True ($sec -lt 20) "bộ cài treo: dừng sau thời hạn, không thử lại ($sec giây)"
    Assert-Equal 0 @(Get-CimInstance Win32_Process -Filter "Name='PING.EXE'" | Where-Object { $_.CommandLine -match '-n 31' }).Count 'bộ cài treo: dừng cả tiến trình con'

    # ---- trạng thái
    $ChayThu = $false
    $st = New-State
    Set-StepResult $st 'winget' 'xong' 'v1'
    Set-StepResult $st 'winget' 'loi' 'v2'
    Save-State $st
    $back = Read-State
    Assert-Equal 'loi' (Get-StepStatus $back 'winget') 'trạng thái ghi rồi đọc lại'
    Assert-Equal '' (Get-StepStatus $back 'driver') 'bước chưa chạy: rỗng'

    # ---- đổi tên máy (chạy thử)
    $ChayThu = $true
    function Set-KhoiDong { param([string]$Name) [IO.File]::WriteAllText((Join-Path $env:AUTOSETUP_GOC 'KhoiDong.json'), (ConvertTo-JsonText ([ordered]@{ tenMayNhap = $Name })), (New-Object Text.UTF8Encoding $false)) }
    Set-KhoiDong ''
    Assert-Equal 'bo-qua' (Invoke-StepTenMay $st)[0] 'không nhập tên máy: bỏ qua'
    Set-KhoiDong '$$TEN_MAY$$'
    Assert-Equal 'bo-qua' (Invoke-StepTenMay $st)[0] 'biến Ventoy chưa điền: bỏ qua'
    Set-KhoiDong 'MAY TINH'
    Assert-Equal 'loi' (Invoke-StepTenMay $st)[0] 'tên có dấu cách: lỗi'
    Set-KhoiDong $env:COMPUTERNAME
    Assert-Equal 'xong' (Invoke-StepTenMay $st)[0] 'trùng tên hiện tại: xong'
    Set-KhoiDong 'KETOAN-01'
    Assert-Equal 'chay-thu' (Invoke-StepTenMay $st)[0] 'tên hợp lệ: chạy thử không đổi'
    $ChayThu = $false

    # ---- chạy thử cả lượt trên bản sao (USB giả, không mạng; bật Office, tắt driver)
    $usb = Join-Path $d 'usb'
    $as = Join-Path $usb 'AutoSetup'
    Copy-Item (Join-Path $script:Repo 'sau-cai') (Join-Path $as 'sau-cai') -Recurse
    New-Item -ItemType Directory -Path (Join-Path $as 'cau-hinh'), (Join-Path $as 'office') -Force | Out-Null
    $cfg = [IO.File]::ReadAllText((Join-Path $script:Repo 'cau-hinh\CauHinh.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $cfg.sauCai.driver = $false
    Write-JsonFile (Join-Path $as 'cau-hinh\CauHinh.json') $cfg
    Copy-Item (Join-Path $script:Repo 'cau-hinh\UngDung.json') (Join-Path $as 'cau-hinh')
    [IO.File]::WriteAllText((Join-Path $as 'office\setup.exe'), '')
    $env:AUTOSETUP_USB = $usb
    $env:AUTOSETUP_GOC = Join-Path $d 'goc2'
    $env:AUTOSETUP_TEST_MANG = '0'
    $r = Invoke-Ps (Join-Path $as 'sau-cai\SauCai.ps1') @('-ChayThu', '-KhongDung')
    Assert-Equal 0 $r.Code 'chạy thử cả lượt: mã 0'
    Assert-True ($r.Text -match 'TỔNG KẾT') 'chạy thử cả lượt: có tổng kết'
    Assert-True ($r.Text -match 'Chuẩn bị winget\s+chờ mạng') 'không mạng: winget chờ mạng'
    Assert-True ($r.Text -match 'Driver\s+bỏ qua') 'driver tắt trong cấu hình: bỏ qua'
    Assert-True (-not (Test-Path (Join-Path $env:AUTOSETUP_GOC 'TrangThai.json'))) 'chạy thử: không ghi trạng thái'
    $r = Invoke-Ps (Join-Path $as 'sau-cai\SauCai.ps1') @('-ChayThu', '-KhongDung', '-Chi', 'khong-co')
    Assert-Equal 1 $r.Code 'bước không có: mã 1'
} finally {
    foreach ($v in 'AUTOSETUP_GOC', 'AUTOSETUP_WINGET', 'AS_FAKE', 'AUTOSETUP_USB', 'AUTOSETUP_TEST_MANG', 'AUTOSETUP_TEST_NAP', 'AUTOSETUP_PORTABLE', 'AUTOSETUP_LOITAT') { Set-Item -Path "env:$v" -Value '' }
    Remove-TestDir $d
}

Complete-Test
