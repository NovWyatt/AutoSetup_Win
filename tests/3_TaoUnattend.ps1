<#
  Sinh file unattend: đủ 6 file, XML hợp lệ, đúng từng biến thể (chọn ổ tay không có lệnh chia ổ; bản xoá ổ có
  bước kiểm tra và chia ổ đúng), lệnh WinPE không quá dài, mỗi dòng tối đa một biến Ventoy, script nhúng giải nén ra
  đúng nội dung; các chế độ bản quyền, tài khoản, tên máy, -DiskId; cấu hình sai thì dừng.
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')
$tao = Join-Path $script:Repo 'scripts\TaoUnattend.ps1'
$nsU = 'urn:schemas-microsoft-com:unattend'
$ventoyVar = '$$VT_WINDOWS_DISK_1ST_NONUSB$$'

function Read-Unattend {
    param([string]$Path)
    $x = New-Object Xml.XmlDocument
    $x.Load($Path)
    $ns = New-Object Xml.XmlNamespaceManager $x.NameTable
    $ns.AddNamespace('u', $nsU)
    $ns.AddNamespace('e', 'https://github.com/NovWyatt/AutoSetup_Win')
    return [pscustomobject]@{ Doc = $x; Ns = $ns }
}
function Select-One { param($U, [string]$XPath) return $U.Doc.SelectSingleNode($XPath, $U.Ns) }
function Select-All { param($U, [string]$XPath) return @($U.Doc.SelectNodes($XPath, $U.Ns)) }

function New-Config {
    # Bản sao cấu hình mặc định trong thư mục tạm, sửa bằng scriptblock.
    param([string]$Dir, [scriptblock]$Edit = {})
    . (Join-Path $script:Repo 'sau-cai\lib\Json.ps1')
    $c = [IO.File]::ReadAllText((Join-Path $script:Repo 'cau-hinh\CauHinh.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    & $Edit $c
    $p = Join-Path $Dir 'CauHinh.json'
    Write-JsonFile $p $c
    return $p
}

$d = New-TestDir 'unattend'
try {
    # ------------------------------------------------ cấu hình mặc định
    $out = Join-Path $d 'mac-dinh'
    $r = Invoke-Ps $tao @('-Ra', $out, '-KhongDung')
    Assert-Equal 0 $r.Code 'sinh với cấu hình mặc định'
    $files = @(Get-ChildItem -LiteralPath $out -Filter '*.xml' | Sort-Object Name)
    Assert-Equal 6 $files.Count 'đủ 6 file'
    $list = [IO.File]::ReadAllText((Join-Path $out 'DanhSach.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-Equal 6 @($list.tep).Count 'DanhSach.json có 6 mục'
    Assert-Equal '1_Chon-o-bang-tay.xml' $list.tep[0].tep 'mục đầu tiên (mặc định của Ventoy) là bản chọn ổ tay'
    Assert-Equal 'False' $list.tep[0].xoaO 'mục đầu tiên không xoá ổ'

    foreach ($f in $files) {
        $n = $f.BaseName
        $u = Read-Unattend $f.FullName
        $wipe = $n -like '*XOA-SACH*'
        $post = $n -notlike '*Chi-Windows*'
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        Assert-True ($bytes[0] -ne 0xEF) "$n UTF-8 không BOM"
        $lines = [IO.File]::ReadAllLines($f.FullName)
        Assert-True (-not @($lines | Where-Object { ([regex]::Matches($_, '\$\$[A-Za-z0-9_]+\$\$')).Count -gt 1 }).Count) "$n mỗi dòng tối đa một biến Ventoy"
        # Setup chép file vào Panther và đổi chữ ngoài ASCII thành '?' (thấy khi thử máy ảo 2026-10-12).
        $nonAscii = @($u.Doc.SelectNodes('//text() | //@*') | Where-Object { $_.Value -match '[^\x00-\x7F]' })
        Assert-Equal 0 $nonAscii.Count "$n chữ trong file chỉ có ASCII"
        Assert-Equal 3 (Select-All $u "//e:Extensions/e:File[@ma='base64']").Count "$n ba script nhúng dạng base64"
        $paths = Select-All $u '//u:RunSynchronousCommand/u:Path'
        Assert-True (-not @($paths | Where-Object { $_.InnerText.Length -gt 255 }).Count) "$n mọi lệnh RunSynchronous tối đa 255 ký tự"
        $orders = @(Select-All $u "//u:settings[@pass='windowsPE']//u:RunSynchronousCommand/u:Order" | ForEach-Object { [int]$_.InnerText })
        Assert-True (($orders -join ',') -eq ((1..$orders.Count) -join ',')) "$n thứ tự lệnh WinPE liên tục 1..$($orders.Count)"
        Assert-True ($null -eq (Select-One $u '//u:ProductKey/u:Key')) "$n bản quyền BIOS: không ghi key"
        Assert-Equal 'OnError' (Select-One $u '//u:ProductKey/u:WillShowUI').InnerText "$n hỏi key khi BIOS không có"
        Assert-Equal '*' (Select-One $u '//u:ComputerName').InnerText "$n tên máy ngẫu nhiên"
        Assert-Equal 'false' (Select-One $u '//u:HideLocalAccountScreen').InnerText "$n OOBE hỏi tài khoản"
        Assert-True ($null -eq (Select-One $u '//u:UserAccounts')) "$n không tự tạo tài khoản"
        Assert-Equal 5 @(Select-All $u "//u:RunSynchronousCommand[contains(u:Path,'LabConfig')]").Count "$n bỏ kiểm tra TPM, Secure Boot, RAM, CPU, ổ"
        $guard = @($paths | Where-Object { $_.InnerText -like '*as-kt.vbs*' })
        if ($wipe) {
            Assert-Equal 'true' (Select-One $u '//u:DiskConfiguration/u:Disk/u:WillWipeDisk').InnerText "$n xoá ổ"
            Assert-Equal $ventoyVar (Select-One $u '//u:DiskConfiguration/u:Disk/u:DiskID').InnerText "$n ổ lấy từ biến Ventoy (không phải USB)"
            Assert-Equal $ventoyVar (Select-One $u '//u:InstallTo/u:DiskID').InnerText "$n cài vào cùng ổ"
            Assert-Equal '3' (Select-One $u '//u:InstallTo/u:PartitionID').InnerText "$n cài vào phân vùng 3"
            $last = $guard[-1].InnerText
            Assert-True ($last -like "cmd.exe /c `"cscript.exe //nologo //E:vbscript X:\as-kt.vbs $ventoyVar * || wpeutil.exe reboot`"") "$n chạy kiểm tra ổ, sai thì khởi động lại"
            Assert-True ($guard.Count -gt 20) "$n ghi script kiểm tra ổ ($($guard.Count) lệnh)"
            $sizes = @(Select-All $u '//u:CreatePartition' | ForEach-Object { $s = $_.SelectSingleNode('u:Size', $u.Ns); if ($s) { $s.InnerText } else { 'extend' } })
            if ($n -like '*C-D*') {
                Assert-Equal '300,16,153600,extend' ($sizes -join ',') "$n chia EFI 300, MSR 16, C 150 GB, D phần còn lại"
                Assert-True ($last -match ' 170 \|\|') "$n cần ổ tối thiểu C + 20 GB = 170 GB"
                Assert-Equal 'DATA' (Select-One $u "//u:ModifyPartition[u:PartitionID='4']/u:Label").InnerText "$n phân vùng 4 nhãn DATA"
                Assert-True ($null -eq (Select-One $u "//u:ModifyPartition[u:PartitionID='4']/u:Letter")) "$n không gán chữ ổ cho DATA trong WinPE"
            } else {
                Assert-Equal '300,16,extend' ($sizes -join ',') "$n chia EFI 300, MSR 16, C phần còn lại"
                Assert-True ($last -match ' 60 \|\|') "$n cần ổ tối thiểu 60 GB"
            }
            Assert-Equal 'C' (Select-One $u "//u:ModifyPartition[u:PartitionID='3']/u:Letter").InnerText "$n phân vùng Windows là C"
        } else {
            Assert-True ($null -eq (Select-One $u '//u:DiskConfiguration')) "$n không có lệnh chia ổ"
            Assert-True ($null -eq (Select-One $u '//u:ImageInstall')) "$n không chỉ định ổ cài"
            Assert-Equal 0 $guard.Count "$n không có script kiểm tra ổ"
        }

        # Giải nén script nhúng như bước specialize, nhưng vào thư mục tạm, từ bản đã bị đổi chữ ngoài ASCII thành '?'
        # như bản Setup chép vào Panther.
        $ext = Join-Path $d "giai-nen-$n"
        $pan = New-Object Xml.XmlDocument
        $pan.LoadXml([regex]::Replace($u.Doc.OuterXml, '[^\x00-\x7F]', '?'))
        $panU = [pscustomobject]@{ Doc = $pan; Ns = $u.Ns }
        foreach ($fe in Select-All $panU '//e:Extensions/e:File') { $fe.SetAttribute('path', $fe.GetAttribute('path').Replace('C:\Windows\Setup\Scripts', $ext)) }
        $sb = [scriptblock]::Create((Select-One $panU '//e:ExtractScript').InnerText)
        & $sb $pan
        foreach ($s in 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1') {
            $p = Join-Path $ext $s
            $src = [IO.File]::ReadAllText((Join-Path $script:Repo "unattend\scripts\$s"), [Text.Encoding]::UTF8).Trim() -replace "`r`n", "`n"
            $got = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8).Trim() -replace "`r`n", "`n"
            Assert-True ($got -ceq $src) "$n giải nén $s đúng nội dung"
            $b = [IO.File]::ReadAllBytes($p)
            Assert-True ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) "$n $s có BOM sau giải nén"
        }
        $info = [IO.File]::ReadAllText((Join-Path $ext 'AutoSetup.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        Assert-Equal $n $info.bienThe "$n AutoSetup.json đúng biến thể"
        Assert-Equal ([string]$post) ([string]$info.sauCai) "$n AutoSetup.json sauCai = $post"
        Assert-Equal '' $info.tenMayNhap "$n không hỏi tên máy"
        Assert-True (@($info.goBo.ungDung).Count -ge 10) "$n mang theo danh sách gỡ ứng dụng"
    }

    # ------------------------------------------------ tài khoản tự tạo + mật khẩu, key chung, tên máy cố định, DiskId
    $cfg2 = New-Config $d { param($c) $c.taiKhoan.cheDo = 'tu-dong'; $c.taiKhoan.ten = 'KeToan'; $c.taiKhoan.tenHienThi = 'Kế toán'; $c.banQuyen.cheDo = 'key-chung'; $c.banQuyen.phienBanWindows = 'pro'; $c.tenMay = 'KETOAN-01'; $c.oobe.hienWifi = $false }
    $pwFile = Join-Path $d 'mk.txt'
    [IO.File]::WriteAllText($pwFile, "Mk@2026!`r`n", (New-Object Text.UTF8Encoding $false))
    $out2 = Join-Path $d 'tu-dong'
    $r = Invoke-Ps $tao @('-CauHinh', $cfg2, '-Ra', $out2, '-MatKhauFile', $pwFile, '-DiskId', '0', '-KhongDung')
    Assert-Equal 0 $r.Code 'sinh với tài khoản tự tạo'
    $u = Read-Unattend (Join-Path $out2 '1_Chon-o-bang-tay.xml')
    Assert-Equal 'KeToan' (Select-One $u '//u:LocalAccount/u:Name').InnerText 'tạo tài khoản KeToan'
    Assert-Equal 'Ke toan' (Select-One $u '//u:LocalAccount/u:DisplayName').InnerText 'tên hiển thị trong unattend bỏ dấu'
    $asj = (Select-One $u "//e:Extensions/e:File[contains(@path, 'AutoSetup.json')]").InnerText | ConvertFrom-Json
    Assert-Equal 'Kế toán' $asj.taiKhoan.tenHienThi 'AutoSetup.json giữ tên hiển thị có dấu cho FirstLogon'
    Assert-Equal 0 @($u.Doc.SelectNodes('//text() | //@*') | Where-Object { $_.Value -match '[^\x00-\x7F]' }).Count 'tài khoản có dấu: file vẫn chỉ có ASCII'
    Assert-Equal 'Administrators' (Select-One $u '//u:LocalAccount/u:Group').InnerText 'tài khoản quản trị'
    $expect = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Mk@2026!Password'))
    Assert-Equal $expect (Select-One $u '//u:LocalAccount/u:Password/u:Value').InnerText 'mật khẩu che kiểu Windows SIM'
    Assert-Equal 'false' (Select-One $u '//u:LocalAccount/u:Password/u:PlainText').InnerText 'mật khẩu không để dạng chữ thường'
    Assert-True ([IO.File]::ReadAllText((Join-Path $out2 '1_Chon-o-bang-tay.xml')) -notmatch 'Mk@2026') 'không có mật khẩu dạng chữ trong file'
    Assert-Equal '1' (Select-One $u '//u:AutoLogon/u:LogonCount').InnerText 'tự đăng nhập một lần'
    Assert-Equal 'true' (Select-One $u '//u:HideLocalAccountScreen').InnerText 'OOBE không hỏi tài khoản'
    Assert-Equal 'true' (Select-One $u '//u:HideWirelessSetupInOOBE').InnerText 'OOBE không hỏi Wi-Fi'
    Assert-Equal 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' (Select-One $u '//u:ProductKey/u:Key').InnerText 'key cài đặt chung của Pro'
    Assert-Equal 'KETOAN-01' (Select-One $u '//u:ComputerName').InnerText 'tên máy cố định'
    $u3 = Read-Unattend (Join-Path $out2 '3_XOA-SACH-o_1-phan-vung.xml')
    Assert-Equal '0' (Select-One $u3 '//u:DiskConfiguration/u:Disk/u:DiskID').InnerText '-DiskId 0 ghi cố định ổ'
    Assert-True (@(Select-All $u3 '//u:RunSynchronousCommand/u:Path' | Where-Object { $_.InnerText -like '*as-kt.vbs 0 60 ||*' }).Count -eq 1) '-DiskId 0 truyền cho bước kiểm tra ổ'
    Assert-True ([IO.File]::ReadAllText((Join-Path $out2 '3_XOA-SACH-o_1-phan-vung.xml')) -notmatch '\$\$VT_') '-DiskId: không còn biến Ventoy'

    $r = Invoke-Ps $tao @('-CauHinh', $cfg2, '-Ra', (Join-Path $d 'trong'), '-KhongMatKhau', '-KhongDung')
    $u = Read-Unattend (Join-Path $d 'trong\1_Chon-o-bang-tay.xml')
    Assert-Equal 'true' (Select-One $u '//u:LocalAccount/u:Password/u:PlainText').InnerText '-KhongMatKhau: mật khẩu trống'

    # ------------------------------------------------ hỏi key, hỏi tên máy
    $cfg3 = New-Config $d { param($c) $c.banQuyen.cheDo = 'hoi'; $c.tenMay = 'hoi'; $c.oobe.boQuaKiemTraPhanCung = $false }
    $out3 = Join-Path $d 'hoi'
    $r = Invoke-Ps $tao @('-CauHinh', $cfg3, '-Ra', $out3, '-KhongDung')
    Assert-Equal 0 $r.Code 'sinh với chế độ hỏi'
    $u = Read-Unattend (Join-Path $out3 '1_Chon-o-bang-tay.xml')
    Assert-Equal '00000-00000-00000-00000-00000' (Select-One $u '//u:ProductKey/u:Key').InnerText 'hỏi key: key rỗng'
    Assert-Equal 'Always' (Select-One $u '//u:ProductKey/u:WillShowUI').InnerText 'hỏi key: luôn hiện trang key'
    Assert-Equal '*' (Select-One $u '//u:ComputerName').InnerText 'hỏi tên máy: Setup đặt tên ngẫu nhiên trước'
    $txt = [IO.File]::ReadAllText((Join-Path $out3 '1_Chon-o-bang-tay.xml'), [Text.Encoding]::UTF8)
    Assert-True ($txt -match '"tenMayNhap": "\$\$TEN_MAY\$\$"') 'hỏi tên máy: biến Ventoy $$TEN_MAY$$'
    Assert-True ($null -eq (Select-One $u "//u:settings[@pass='windowsPE']//u:RunSynchronous")) 'không bỏ kiểm tra phần cứng: không có lệnh WinPE ở bản chọn ổ tay'

    # ------------------------------------------------ cấu hình sai
    $cfg4 = New-Config $d { param($c) $c.banQuyen.cheDo = 'sai' }
    $r = Invoke-Ps $tao @('-CauHinh', $cfg4, '-Ra', (Join-Path $d 'sai'), '-KhongDung')
    Assert-Equal 1 $r.Code 'cấu hình sai: mã thoát 1'
    Assert-True ($r.Text -match 'banQuyen.cheDo') 'cấu hình sai: báo đúng khoá'
    $r = Invoke-Ps $tao @('-Ra', (Join-Path $d 'sai2'), '-DiskId', 'abc', '-KhongDung')
    Assert-Equal 1 $r.Code '-DiskId không phải số: mã thoát 1'
} finally { Remove-TestDir $d }

Complete-Test
