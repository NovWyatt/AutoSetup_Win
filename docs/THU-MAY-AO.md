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
- Máy ảo 2 nhân có lần treo ở màn UEFI ngay khi bật; lần khác treo khi WinPE khởi động lại sau bước chép file. Gặp thì tắt
  hẳn (`VBoxManage controlvm <tên> poweroff`) rồi bật lại: Setup chạy tiếp từ chỗ dừng.
- Không chụp snapshot, không tạm dừng khi máy ảo đang chạy, không "save state" rồi chạy tiếp: trên máy dùng Hyper-V
  các thao tác này hay làm máy ảo đứng hẳn.
- RAM máy thật cần trống ít nhất 2 GB ngoài phần cho máy ảo; thiếu RAM thì máy ảo đứng từng lúc (đĩa ảo bị reset).
- DNS của mạng NAT hay hỏng: `TaoMayAo.ps1` bật `--natdnshostresolver1 on`. Thiếu DNS thì OOBE chậm tới mức Windows
  khởi động lại OOBE ("Why did my PC restart?"), winget không tải được.
- Màn hình máy ảo tắt sau vài phút không bấm gì: bấm Ctrl để sáng lại (đừng bấm Shift 5 lần: bật Sticky Keys).

## Kết quả lần thử 12/10/2026

Windows 11 build 26300 (ISO tiếng Anh), VirtualBox 7.2 trên Windows 11 có Hyper-V, máy ảo UEFI + TPM 2.0 + Secure Boot,
4 nhân, 3,5 GB RAM, ổ 64 GB, bản `3_XOA-SACH-o_1-phan-vung`, cấu hình mặc định.

| Giai đoạn | Kết quả |
|---|---|
| WinPE | Đoạn kiểm tra ổ cho qua (một ổ, UEFI, đủ dung lượng); bỏ qua trang chọn ngôn ngữ; xoá ổ, tạo GPT: EFI 300 MB, MSR, C (Setup tự thêm phân vùng Recovery khoảng 900 MB sau C) |
| Key | Máy ảo không có key trong BIOS nên Setup hỏi key rồi cho chọn phiên bản: đúng thiết kế (`banQuyen.cheDo: key-chung` để bỏ trang này) |
| specialize | Specialize.ps1, DefaultUser.ps1 chạy đúng (gỡ ứng dụng cài sẵn, chỉnh mặc định cho tài khoản mới) |
| OOBE | Có mạng vẫn vào thẳng trang tạo tài khoản local; trang quyền riêng tư bị ẩn |
| Đăng nhập đầu | Taskbar căn trái, ẩn Task View, định dạng ngày vi-VN; FirstLogon chép bước sau cài từ ISO vào `C:\AutoSetup`, tạo tác vụ, chạy SauCai |
| Sau cài | Ổ dữ liệu: bỏ qua đúng (chỉ có C); winget sẵn sàng; cài Zalo, UniKey, 7-Zip, Foxit, UltraViewer, Chrome, VC++; Office bỏ qua (không có bộ cài); Windows Update không còn driver nào; báo cáo tự mở; tác vụ tự chạy tự xoá khi xong |
| Máy hai ổ | Máy ảo 2 ổ (64 + 80 GB), cùng bản 3: WinPE báo "May co 2 o cung trong..." rồi khởi động lại; hai ổ vẫn trống (không bị ghi) |

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
