<#
  Chép lên USB (thư mục giả làm USB Ventoy): đủ thư mục AutoSetup; ventoy.json giữ nguyên cấu hình cũ (theme, mục
  auto_install của ISO khác), thêm menu cho ISO Windows, bỏ qua ISO không phải Windows, sao lưu bản cũ; chạy lại
  không đổi gì; chạy thử không ghi gì.
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')
. (Join-Path $script:Repo 'sau-cai\lib\Json.ps1')
$tao = Join-Path $script:Repo 'scripts\TaoUSB.ps1'

$d = New-TestDir 'taousb'
try {
    $env:AUTOSETUP_OUT = Join-Path $d 'out'
    # Bản sao cấu hình mặc định: không dính CauHinh.local.json, UngDung.local.json của người chạy bài thử.
    $env:AUTOSETUP_CAUHINH = Join-Path $d 'cau-hinh'
    New-Item -ItemType Directory -Path $env:AUTOSETUP_CAUHINH -Force | Out-Null
    foreach ($f in 'CauHinh.json', 'UngDung.json') { Copy-Item (Join-Path $script:Repo "cau-hinh\$f") $env:AUTOSETUP_CAUHINH }
    $usb = Join-Path $d 'usb'
    New-Item -ItemType Directory -Path (Join-Path $usb 'ISO\Windows'), (Join-Path $usb 'ISO\Linux'), (Join-Path $usb 'ventoy') -Force | Out-Null
    foreach ($f in 'ISO\Windows\Win11_26300_x64_en-US.iso', 'ISO\Windows\Windows 10 22H2.iso', 'ISO\Linux\ubuntu-24.04.iso') { [IO.File]::WriteAllText((Join-Path $usb $f), '') }
    $old = [ordered]@{
        control      = @([ordered]@{ VTOY_DEFAULT_MENU_MODE = '0' })
        theme        = [ordered]@{ file = '/ventoy/theme/x/theme.txt' }
        auto_install = @([ordered]@{ image = '/ISO/Linux/ubuntu-24.04.iso'; template = '/ventoy/script/ubuntu.cfg' })
    }
    Write-JsonFile (Join-Path $usb 'ventoy\ventoy.json') $old

    $r = Invoke-Ps $tao @('-O', $usb, '-ChayThu', '-KhongDung')
    Assert-Equal 0 $r.Code 'chạy thử: mã 0'
    Assert-True (-not (Test-Path (Join-Path $usb 'AutoSetup'))) 'chạy thử: không tạo AutoSetup'
    Assert-True ($r.Text -match 'Win11_26300_x64_en-US\.iso') 'chạy thử: liệt kê ISO Windows'

    $r = Invoke-Ps $tao @('-O', $usb, '-KhongDung')
    Assert-Equal 0 $r.Code "chép lên USB: mã 0 $(if ($r.Code) { $r.Text })"
    foreach ($p in 'AutoSetup\sau-cai\SauCai.ps1', 'AutoSetup\sau-cai\CHAY_LAI.bat', 'AutoSetup\sau-cai\lib\UngDung.ps1', 'AutoSetup\cau-hinh\CauHinh.json', 'AutoSetup\cau-hinh\UngDung.json',
        'AutoSetup\unattend\1_Chon-o-bang-tay.xml', 'AutoSetup\unattend\6_XOA-SACH-o_chia-C-D_Chi-Windows.xml', 'AutoSetup\office\DOC-TRUOC.txt', 'AutoSetup\drivers\DOC-TRUOC.txt', 'AutoSetup\ket_qua') {
        Assert-True (Test-Path (Join-Path $usb $p)) "có $p"
    }
    $v = Read-JsonFile (Join-Path $usb 'ventoy\ventoy.json')
    Assert-Equal '/ventoy/theme/x/theme.txt' $v.theme.file 'giữ theme cũ'
    Assert-Equal '0' $v.control[0].VTOY_DEFAULT_MENU_MODE 'giữ control cũ'
    $ai = @($v.auto_install)
    Assert-Equal 3 $ai.Count 'auto_install: 1 mục cũ + 2 ISO Windows'
    Assert-True (@($ai | Where-Object { $_.image -eq '/ISO/Linux/ubuntu-24.04.iso' -and $_.template -eq '/ventoy/script/ubuntu.cfg' }).Count -eq 1) 'giữ mục auto_install của ISO khác'
    $w11 = @($ai | Where-Object { $_.image -eq '/ISO/Windows/Win11_26300_x64_en-US.iso' })
    Assert-Equal 1 $w11.Count 'thêm mục cho ISO Windows 11'
    Assert-Equal 6 @($w11[0].template).Count 'mục ISO có 6 lựa chọn'
    Assert-Equal '/AutoSetup/unattend/1_Chon-o-bang-tay.xml' @($w11[0].template)[0] 'lựa chọn đầu là chọn ổ tay'
    Assert-Equal 1 $w11[0].autosel 'mặc định chọn mục 1'
    Assert-Equal 15 $w11[0].timeout 'chờ 15 giây'
    Assert-True (@($ai | Where-Object { $_.image -eq '/ISO/Windows/Windows 10 22H2.iso' }).Count -eq 1) 'nhận ISO Windows 10 có dấu cách'
    Assert-Equal 1 @(Get-ChildItem (Join-Path $usb 'ventoy') -Filter 'ventoy.json.bak-*').Count 'sao lưu ventoy.json cũ'
    $raw = [IO.File]::ReadAllText((Join-Path $usb 'ventoy\ventoy.json'))
    Assert-True ($raw -notmatch '\\u00') 'ventoy.json không có ký tự \u00..'
    $b = [IO.File]::ReadAllBytes((Join-Path $usb 'ventoy\ventoy.json'))
    Assert-True ($b[0] -ne 0xEF) 'ventoy.json không BOM'

    $r = Invoke-Ps $tao @('-O', $usb, '-KhongSinhLai', '-KhongDung')
    Assert-Equal 0 $r.Code 'chạy lại: mã 0'
    Assert-True ($r.Text -match 'ventoy.json đã đúng') 'chạy lại: ventoy.json không đổi'
    Assert-Equal 1 @(Get-ChildItem (Join-Path $usb 'ventoy') -Filter 'ventoy.json.bak-*').Count 'chạy lại: không sao lưu thêm'

    Remove-Item (Join-Path $usb 'ISO\Windows\Windows 10 22H2.iso')
    $r = Invoke-Ps $tao @('-O', $usb, '-KhongSinhLai', '-KhongDung')
    $ai = @((Read-JsonFile (Join-Path $usb 'ventoy\ventoy.json')).auto_install)
    Assert-Equal 2 $ai.Count 'xoá ISO: bỏ mục AutoSetup cũ của ISO đó'

    $r = Invoke-Ps $tao @('-O', $env:SystemDrive, '-ChayThu', '-KhongDung')
    Assert-Equal 1 $r.Code 'từ chối chép vào ổ Windows'
} finally {
    $env:AUTOSETUP_OUT = ''
    $env:AUTOSETUP_CAUHINH = ''
    Remove-TestDir $d
}

Complete-Test
