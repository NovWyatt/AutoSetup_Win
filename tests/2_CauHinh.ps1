<#
  Cấu hình và JSON: cấu hình mặc định hợp lệ; cấu hình sai bị bắt đúng chỗ; CauHinh.local.json ghi đè đúng;
  bộ ghi JSON giữ nguyên chữ, mảng một phần tử, đọc lại ra cùng giá trị; danh sách ứng dụng không trùng.
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')
. (Join-Path $script:Repo 'scripts\lib\CauHinh.ps1')

$cfgPath = Join-Path $script:Repo 'cau-hinh\CauHinh.json'
$cfg = Read-JsonFile $cfgPath
$errs = Test-AutoSetupConfig $cfg
Assert-Equal 0 $errs.Count ("cấu hình mặc định hợp lệ " + ($errs -join '; '))
Assert-Equal 'bios' $cfg.banQuyen.cheDo 'mặc định bản quyền theo BIOS'
Assert-Equal 'hoi' $cfg.taiKhoan.cheDo 'mặc định hỏi tài khoản ở OOBE'
Assert-Equal 1 $cfg.ventoy.macDinh 'mặc định menu Ventoy là mục 1 (không xoá ổ)'

function Test-Bad {
    param([string]$Path, $Value, [string]$Expect)
    $c = Read-JsonFile $cfgPath
    $parts = $Path.Split('.')
    $o = $c
    for ($i = 0; $i -lt $parts.Count - 1; $i++) { $o = $o.($parts[$i]) }
    $o.($parts[-1]) = $Value
    $e = Test-AutoSetupConfig $c
    Assert-True (@($e | Where-Object { $_ -like "*$Expect*" }).Count) "bắt lỗi $Path = '$Value'"
}
Test-Bad 'banQuyen.cheDo' 'crack' 'banQuyen.cheDo'
Test-Bad 'taiKhoan.cheDo' 'x' 'taiKhoan.cheDo'
Test-Bad 'tenMay' 'MAY TINH 1' 'tenMay'
Test-Bad 'tenMay' 'TEN-MAY-QUA-DAI-16' 'tenMay'
Test-Bad 'tenMay' '12345' 'tenMay'
Test-Bad 'ngonNgu.giaoDien' 'tieng viet' 'ngonNgu.giaoDien'
Test-Bad 'ngonNgu.banPhim' 'US' 'ngonNgu.banPhim'
Test-Bad 'oDia.dungLuongC_GB' 10 'oDia.dungLuongC_GB'
Test-Bad 'tinhChinh.timKiem' 'to' 'tinhChinh.timKiem'
Test-Bad 'sauCai.thuMucCai' 'Program Files' 'sauCai.thuMucCai'
Test-Bad 'ventoy.macDinh' 9 'ventoy.macDinh'
$c = Read-JsonFile $cfgPath
$c.taiKhoan.cheDo = 'tu-dong'; $c.taiKhoan.ten = 'Administrator'
Assert-True (@(Test-AutoSetupConfig $c | Where-Object { $_ -like '*taiKhoan.ten*' }).Count) 'không cho tài khoản tên Administrator'
$c.taiKhoan.ten = 'Kế Toán'
Assert-True (@(Test-AutoSetupConfig $c | Where-Object { $_ -like '*taiKhoan.ten*' }).Count) 'không cho tên tài khoản có dấu (Setup đổi thành ?)'
$c.taiKhoan.ten = 'Ke Toan'
Assert-Equal 0 (Test-AutoSetupConfig $c).Count 'tài khoản có dấu cách hợp lệ'
$c = Read-JsonFile $cfgPath
$c.banQuyen.cheDo = 'key-chung'; $c.banQuyen.phienBanWindows = 'ultimate'
Assert-True (@(Test-AutoSetupConfig $c | Where-Object { $_ -like '*phienBanWindows*' }).Count) 'key-chung cần phiên bản có trong bảng'

# ---- ghi đè bằng CauHinh.local.json
$d = New-TestDir 'cauhinh'
try {
    Copy-Item $cfgPath (Join-Path $d 'CauHinh.json')
    [IO.File]::WriteAllText((Join-Path $d 'CauHinh.local.json'), '{ "_ghiChu": "x", "tenMay": "KETOAN-01", "sauCai": { "office": false }, "goBo": { "ungDung": ["A.B"] } }', (New-Object Text.UTF8Encoding $false))
    $m = Get-AutoSetupConfig (Join-Path $d 'CauHinh.json')
    Assert-Equal 'KETOAN-01' $m.tenMay 'local ghi đè giá trị đơn'
    Assert-Equal 'False' $m.sauCai.office 'local ghi đè khoá con'
    Assert-Equal 'True' $m.sauCai.driver 'local giữ khoá con không nhắc tới'
    Assert-Equal 1 @($m.goBo.ungDung).Count 'local thay cả mảng'
    Assert-True (-not $m.PSObject.Properties['_ghiChu']) 'khoá _ghiChu bị bỏ qua'
} finally { Remove-TestDir $d }

# ---- bộ ghi JSON
$obj = [ordered]@{ chu = "Tiếng Việt 'nháy' <thẻ> & \ `"kép`""; so = 5; thuc = 1.5; dung = $true; rong = $null; mot = @('x'); trong = @(); con = [ordered]@{ a = @(1, 2) } }
$text = ConvertTo-JsonText $obj
Assert-True ($text -match 'Tiếng Việt') 'JSON giữ nguyên chữ tiếng Việt'
Assert-True ($text -notmatch '\\u00') 'JSON không đổi ký tự thành \u00..'
$back = $text | ConvertFrom-Json
Assert-Equal $obj.chu $back.chu 'JSON đọc lại đúng chuỗi có ký tự đặc biệt'
Assert-Equal 1 @($back.mot).Count 'JSON giữ mảng một phần tử'
Assert-Equal 0 @($back.trong).Count 'JSON giữ mảng rỗng'
Assert-Equal '1.5' ([string]$back.thuc) 'JSON số thực dùng dấu chấm'
Assert-Equal 2 $back.con.a[1] 'JSON lồng nhau'

# ---- danh sách ứng dụng
$apps = @((Read-JsonFile (Join-Path $script:Repo 'cau-hinh\UngDung.json')).ungDung)
Assert-True ($apps.Count -ge 10) "UngDung.json có $($apps.Count) ứng dụng"
Assert-Equal $apps.Count @($apps.khoa | Sort-Object -Unique).Count 'khoa không trùng'
Assert-Equal $apps.Count @($apps.id | Sort-Object -Unique).Count 'id không trùng'
Assert-True (-not @($apps | Where-Object { -not $_.ten -or $_.macDinh -isnot [bool] -or $_.khoa -notmatch '^[A-Za-z0-9]+$' }).Count) 'mỗi ứng dụng có ten, macDinh true/false, khoa chữ số'
foreach ($g in @($apps | Where-Object { $_.nhom } | Group-Object nhom)) {
    Assert-True (@($g.Group | Where-Object { $_.macDinh }).Count -le 1) "nhóm $($g.Name) có tối đa một ứng dụng mặc định"
}

Complete-Test
