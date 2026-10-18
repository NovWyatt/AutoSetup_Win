# Thử trên máy ảo (VirtualBox)

Thử trên máy ảo trước khi dùng cho máy khách. Không cần Ventoy: ISO thử chứa `\AutoSetup` và một bản unattend đặt tên
`autounattend.xml` ở gốc; Windows Setup tự đọc file này từ mọi ổ.

## Các bước

1. Cài [VirtualBox](https://www.virtualbox.org) 7.x, tải ISO Windows 10/11.
2. Dựng ISO thử (mặc định bản `3_XOA-SACH-o_1-phan-vung`, ổ số 0):

   ```bat
   powershell -ExecutionPolicy Bypass -File tests\may-ao\TaoIsoThu.ps1
   ```

   Chọn bản khác bằng `-BienThe 1_Chon-o-bang-tay`. Cấu hình lấy từ `cau-hinh\` như `TAO_USB.bat` (muốn thử cấu hình
   riêng thì tạo `CauHinh.local.json`).
3. Tạo máy ảo và khởi động:

   ```bat
   powershell -ExecutionPolicy Bypass -File tests\may-ao\TaoMayAo.ps1 -IsoWin D:\ISO\Win11_x64.iso -Chay
   ```

   Thử bản xoá ổ bị chặn khi máy có hai ổ: `-Ten AutoSetup-Thu2 -OGB 64,80`.
4. Xem trong cửa sổ VirtualBox. Cài xong, báo cáo ở `C:\AutoSetup\ket_qua` trong máy ảo (ISO là đĩa chỉ đọc nên không
   chép báo cáo ra được, bước báo cáo chỉ báo không chép được).

## Kinh nghiệm

- **Máy thật bật Hyper-V** (WSL2, Docker, Memory Integrity...): VirtualBox chạy chậm hẳn qua lớp Hyper-V. Máy ảo 4 nhân
  có lúc dùng hết CPU mà vẫn chậm (một bộ cài 3 MB mất hơn 30 phút), đồng hồ trong máy ảo chạy chậm hơn ngoài. Chờ được,
  không phải lỗi của AutoSetup.
- Số nhân máy ảo: 1 nhân thì Setup báo "The processor needs to have two or more cores" (khoá bỏ kiểm tra phần cứng không
  bỏ được điều kiện này; máy thật đều có từ 2 nhân nên không ảnh hưởng). 2 nhân: trên máy dùng Hyper-V, UEFI hay đứng ở
  bước `DXE_AP` ngay khi bật (cuối `Logs\VBox.log`). 4 nhân: có lần treo, có lần màn hình xanh (BugCheck 0xA trong
  `VBox.log`) ở cuối giai đoạn WinPE, trước khi Setup ghi file khởi động; lần khởi động sau báo "No bootable option or
  device was found". Gặp thì tắt hẳn (`VBoxManage controlvm <tên> poweroff`), tạo lại ổ trống rồi cài lại từ đầu.
- Paravirt: để mặc định (Hyper-V) thì 2 lần màn hình xanh 0xA (một lần cuối WinPE, một lần lúc Windows khởi động);
  `--paravirt-provider none` thì không lần nào màn hình xanh, chỉ khựng (hai mục dưới). `TaoMayAo.ps1` đặt sẵn `none`.
- Windows 11 bản mới dùng trình cài kiểu mới: giai đoạn đầu chuẩn bị hệ điều hành trong `C:\$WINDOWS.~BT` ("Installing
  Windows 11 ... % complete"), khởi động lại rồi mới cài tiếp. Log Setup giai đoạn đầu ở
  `C:\$WINDOWS.~BT\Sources\Panther\setupact.log`.
- Không chụp snapshot, không tạm dừng khi máy ảo đang chạy, không "save state" rồi chạy tiếp: trên máy dùng Hyper-V
  các thao tác này hay làm máy ảo đứng hẳn.
- Đừng tắt máy ảo khi Windows đang cài (kể cả màn "Installing X%" sau lần khởi động lại đầu): lần bật sau Setup báo
  "The computer restarted unexpectedly or encountered an unexpected error", phải tạo lại ổ trống và cài lại từ đầu.
- Trên máy dùng Hyper-V, máy ảo nhiều nhân có lúc kẹt hẳn, lúc Windows khởi động lại cũng như giữa chừng (lần 4 gặp 3
  lần: giữa specialize, hai lần trong OOBE): màn hình đen, ổ ảo không đọc ghi gì, các nhân đứng ở cùng một địa chỉ với
  ngắt bị tắt (`VBoxManage debugvm <tên> getregisters --cpu <0..3> rip rflags`, đọc hai lần vẫn y nguyên), `Logs\VBox.log`
  ghi liên tục "TM: Giving up catch-up attempt". Khác với trường hợp chỉ chậm: khi đó bộ đếm đọc ghi
  (`VBoxManage debugvm <tên> statistics --pattern "/Public/Storage/AHCI0/Port0/Bytes*"`) vẫn tăng. Kẹt hẳn thì chỉ còn
  cách tắt hẳn (`VBoxManage controlvm <tên> poweroff`) rồi bật lại. Lúc Windows đang khởi động lại hay đang specialize thì
  Windows chạy tiếp, không hỏng gì. Giữa OOBE thì Windows hiện "Why did my PC restart?": bấm Next (gặp "Something went
  wrong" mã OOBEZDP thì bấm Skip), OOBE chạy lại từ đầu và qua được.
- Đã phải tắt hẳn vì kẹt thì trước khi bật lại, đặt máy ảo còn 1 nhân (`VBoxManage modifyvm <tên> --cpus 1`): Setup chỉ
  đòi từ 2 nhân ở giai đoạn WinPE, Windows đã cài chạy được với 1 nhân. Lần 4 sau khi về 1 nhân không kẹt lần nào nữa
  (chậm hơn).
- Máy ảo có lúc khựng hơn 15 phút giữa chừng (màn hình đứng hình, ổ không đọc ghi), các nhân ảo nằm ở vòng nghỉ chờ ngắt.
  Hai lần đọc thanh ghi từng nhân (`VBoxManage debugvm <tên> getregisters --cpu <0..3> rip`) làm máy ảo chạy lại ngay.
- RAM máy thật cần trống ít nhất 2 GB ngoài phần cho máy ảo; thiếu RAM thì máy ảo đứng từng lúc (đĩa ảo bị reset).
- DNS của mạng NAT hay hỏng: `TaoMayAo.ps1` bật `--natdnshostresolver1 on`. Thiếu DNS thì OOBE chậm tới mức Windows
  khởi động lại OOBE ("Why did my PC restart?"), winget không tải được.
- Màn hình máy ảo tắt sau vài phút không bấm gì: bấm Ctrl để sáng lại (đừng bấm Shift 5 lần: bật Sticky Keys). Phím đầu
  tiên chỉ làm sáng màn hình, không tới cửa sổ đang mở.
- Windows vừa qua OOBE có mạng là Windows Update tải (lần 4 khoảng 1 GB) và cài ngay trong nền. Máy ảo ít nhân gần như
  đứng: cửa sổ bước sau cài mất gần một giờ mới in dòng đầu. Chờ được, máy thật nhanh hơn nhiều.

## Kết quả lần thử 12/10/2026

Windows 11 build 26300 (ISO tiếng Anh), VirtualBox 7.2 trên Windows 11 có Hyper-V, máy ảo UEFI + TPM 2.0 + Secure Boot,
4 nhân, 3,5 GB RAM, ổ 64 GB, bản `3_XOA-SACH-o_1-phan-vung`.

### Lần 1: cấu hình mặc định

| Giai đoạn | Kết quả |
|---|---|
| WinPE | Đoạn kiểm tra ổ cho qua (một ổ, UEFI, đủ dung lượng); bỏ qua trang chọn ngôn ngữ; xoá ổ, tạo GPT: EFI 300 MB, MSR, C (Setup tự thêm phân vùng Recovery khoảng 900 MB sau C) |
| Key | Máy ảo không có key trong BIOS nên Setup hỏi key rồi cho chọn phiên bản: đúng thiết kế (`banQuyen.cheDo: key-chung` để bỏ trang này) |
| specialize | Specialize.ps1, DefaultUser.ps1 chạy đúng (gỡ ứng dụng cài sẵn, chỉnh mặc định cho tài khoản mới) |
| OOBE | Có mạng vẫn vào thẳng trang tạo tài khoản local; trang quyền riêng tư bị ẩn |
| Đăng nhập đầu | Taskbar căn trái, ẩn Task View, định dạng ngày vi-VN; FirstLogon chép bước sau cài từ ISO vào `C:\AutoSetup`, tạo tác vụ, chạy SauCai |
| Sau cài | Ổ dữ liệu: bỏ qua đúng (chỉ có C); winget sẵn sàng; cài Zalo, UniKey, 7-Zip, Foxit, UltraViewer, Chrome, VC++; Office bỏ qua (không có bộ cài); Windows Update không còn driver nào; báo cáo tự mở; tác vụ tự chạy tự xoá khi xong |
| Máy hai ổ | Máy ảo 2 ổ (64 + 80 GB), cùng bản 3: WinPE báo "May co 2 o cung trong..." rồi khởi động lại; hai ổ vẫn trống (không bị ghi) |

### Lần 2: tự động hoàn toàn, sau khi sửa lỗi lần 1

Cấu hình riêng: `tenMay` MAYTHU-02, `banQuyen` key-chung bản Pro, `taiKhoan` tu-dong tên `KeToan`, tên hiển thị
"Kế toán"; ứng dụng UniKey, 7-Zip. Paravirt `none`.

| Giai đoạn | Kết quả |
|---|---|
| WinPE | Không hỏi gì: trang key, chọn phiên bản đều bỏ qua nhờ key chung |
| specialize | Specialize.ps1, DefaultUser.ps1 chạy đúng |
| OOBE | Tự qua hết, tạo tài khoản `KeToan`, tự đăng nhập |
| Đăng nhập đầu | FirstLogon.log đủ dấu tiếng Việt; đặt tên hiển thị "Kế toán" (đọc lại trong SAM đúng); xoá `unattend.xml` trong Panther (có mật khẩu); tạo tác vụ, chạy SauCai |
| Sau cài | Chữ tiếng Việt trong cửa sổ đúng dấu; cài UniKey kèm lối tắt Start, Startup; cài 7-Zip; Windows Update cài 1 driver rồi tự khởi động lại sau 60 giây |
| Sau khởi động lại | Windows tự đăng nhập lại (nhờ lỗi "+1" của LogonCount, xem dưới); UniKey tự mở từ Startup; SauCai chạy tiếp (lần chạy 2) từ bước Driver tới Báo cáo; báo cáo tự mở |
| Dọn dẹp | Tự đăng nhập đã tắt, registry không còn `DefaultPassword`; tác vụ tự xoá; ô tìm kiếm giữ chế độ biểu tượng (`SearchboxTaskbarMode` = 1). Nhưng bí mật LSA `DefaultPassword` vẫn còn (đọc hive `SECURITY` trong ổ ảo): lỗi, đã sửa |

### Lần 3 (17/10/2026): kiểm phần xoá mật khẩu tự đăng nhập

Cùng cấu hình lần 2 (tên máy MAYTHU-03), code từ commit 9f4ac23.

| Mục | Kết quả |
|---|---|
| FirstLogon | Ghi "tự đăng nhập: còn 4 lần cho các lần khởi động lại của bước sau cài" |
| Bí mật LSA | Sau khi bước sau cài xong lượt, hive `SECURITY` không còn `DefaultPassword` (lần 2 còn). Vẫn còn `CachedDefaultPassword` (92 byte, bản Windows giữ thêm cho tự đăng nhập): nay xoá luôn, xem lần 4 |
| Báo cáo | Bản quyền ghi "chưa kích hoạt (Windows nhắc kích hoạt)" |
| Chưa thử được | Lần này Windows Update không có driver nên bước sau cài không khởi động lại; chưa thấy tận mắt tự đăng nhập theo `AutoLogonCount` |

Máy ảo: một lần hỏng giữa WinPE (Windows tự khởi động lại ở khoảng 10%, ổ chưa có file khởi động); 2 nhân lại đứng ở
`DXE_AP`; lần khởi động lại trong OOBE lại treo, tắt hẳn rồi bật lại thì chạy tiếp.

### Lần 4 (17–18/10/2026): xoá cả `CachedDefaultPassword`, tự đăng nhập sau khởi động lại

Cùng cấu hình lần 2 (tên máy MAYTHU-04), code xoá cả hai bí mật LSA (cùng commit với mục này).

| Mục | Kết quả |
|---|---|
| FirstLogon | Như lần 3: xoá `unattend.xml` trong Panther, đặt tên hiển thị "Kế toán", ghi "tự đăng nhập: còn 4 lần" |
| Khởi động lại giữa chừng | Bước sau cài đứng ở bước 1 (xem dưới) nên khởi động lại bằng tay (Win+X > Shut down > Restart). Windows cài bản cập nhật đã tải, rồi tự đăng nhập `KeToan` không hỏi mật khẩu; tác vụ chạy lại SauCai, chạy hết 8 bước |
| Dọn dẹp | `AutoAdminLogon` = 0, không còn `AutoLogonCount` và `DefaultPassword` trong registry; tác vụ tự xoá; hive `SECURITY` chỉ còn `DPAPI_SYSTEM`, `NL$KM`: hết cả `DefaultPassword` lẫn `CachedDefaultPassword`. Nhật ký không có cảnh báo xoá LSA |
| Báo cáo | Như lần 3; UniKey, 7-Zip đã cài; Driver "Không còn gì cần cài" |

Máy ảo: 4 nhân kẹt 3 lần (xem "Kinh nghiệm"), lần tắt giữa OOBE làm Windows hiện "Why did my PC restart?"; về 1 nhân thì
hết kẹt.

Bước "Ổ dữ liệu là D" đứng 45 phút: dịch vụ PushToInstall của Windows kẹt ở trạng thái START_PENDING nên các dịch vụ
bật theo yêu cầu không bật được (smphost, cần cho `Get-Partition`; cả truy vấn WMI bộ đếm hiệu năng cũng đứng). Khởi
động lại thì bước này qua ngay. Đã sửa, xem mục cuối danh sách dưới (chưa thử lại trên máy ảo).

Lỗi tìm ra khi thử và đã sửa:

- **Mất dấu tiếng Việt trong script nhúng:** Windows Setup chép file trả lời vào `C:\Windows\Panther\unattend.xml` và đổi
  mọi chữ ngoài ASCII thành `?`; specialize, oobeSystem đọc bản đó. Nay script nhúng dạng base64, `AutoSetup.json` viết
  `\uXXXX`, tên tài khoản bắt buộc không dấu (tên hiển thị có dấu được FirstLogon đặt lại).
- **Chữ tiếng Việt hiện ô vuông trong cửa sổ bước sau cài:** cửa sổ powershell.exe mặc định dùng font Lucida Console
  không có chữ ư, ả, ầ... Nay script tự chuyển cửa sổ sang Consolas.
- Thanh tiến trình của `Invoke-WebRequest` che chữ đã in: tắt thanh tiến trình.
- Màn hình tắt giữa chừng: giữ màn hình sáng trong lúc chạy.
- UniKey (bản portable của winget) chỉ được giải nén, không có lối tắt, không chạy cùng Windows: nay tạo lối tắt Start,
  Startup và mở luôn (khoá `loiTat`, `tuChay` trong `UngDung.json`).
- Một bộ cài treo làm cả bước sau cài đứng mãi: nay mỗi ứng dụng có giới hạn `sauCai.choCaiPhut` (30 phút).
- Windows 11 đặt lại ô tìm kiếm trên taskbar ở lần đăng nhập đầu của mỗi tài khoản (chế độ 1 thành 2): nay tài khoản mới
  có thêm lệnh RunOnce đặt lại chế độ đã chọn.
- Báo cáo ghi bản quyền "thông báo" (trạng thái Notification) khó hiểu: nay ghi "chưa kích hoạt (...)".
- Bước Driver chạy lại sau khởi động chỉ ghi "Không còn gì cần cài", mất số driver đã cài ở vòng trước: nay ghi thêm tổng.
- **Mật khẩu tài khoản còn trên máy giao khách:** Windows Setup cất mật khẩu tự đăng nhập trong bí mật LSA
  `DefaultPassword` (Windows giữ thêm bản `CachedDefaultPassword`); bước sau cài chỉ đặt `AutoAdminLogon = 0` và xoá giá
  trị registry nên cả hai còn nguyên. Nay xoá cả hai bí mật LSA (khi xong lượt, và ngay ở lần đăng nhập đầu với bản
  không có bước sau cài).
- Số lần tự đăng nhập dựa vào lỗi của Windows: Windows cộng 1 vào `LogonCount` của unattend (tài liệu Microsoft ghi rõ),
  đặt 1 thành tự đăng nhập 2 lần, nên chỉ một lần khởi động lại của bước sau cài được tự đăng nhập. Nay FirstLogon ghi
  thẳng `AutoLogonCount` = 4 (bằng số lần khởi động lại tối đa của bước sau cài); lần khởi động lại để đổi tên máy
  không còn bị tắt tự đăng nhập trước.
- **Lệnh đọc ổ đĩa đứng mãi làm cả bước sau cài đứng** (lần 4): `Get-Partition`, `Get-Disk`, `Get-Volume`,
  `Get-BitLockerVolume` chờ smphost và không ngắt được trong cùng tiến trình. Nay bước `o-du-lieu` và phần ổ đĩa,
  BitLocker của báo cáo chạy trong một powershell.exe riêng (`sau-cai\lib\ChayRieng.ps1`), quá `sauCai.choODiaPhut`
  (5 phút) thì dừng tiến trình đó. Bước `o-du-lieu` quá giờ thì khởi động lại máy một lần rồi chạy lại (lúc đó các bộ
  cài cần dịch vụ khác, như bộ cài `.msi`, cũng có thể đứng); sau khởi động lại vẫn đứng thì báo lỗi, các bước sau vẫn
  chạy, thử lại bằng `CHAY_LAI.bat -Chi o-du-lieu`. Báo cáo ghi "không đọc được" ở mục ổ đĩa thay vì đứng.
