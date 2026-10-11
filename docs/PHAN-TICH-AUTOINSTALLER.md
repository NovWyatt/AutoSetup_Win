# Phân tích 1172005thinh/AutoInstaller (2026-10-11)

AutoSetup_Win bắt đầu từ việc đọc [1172005thinh/AutoInstaller](https://github.com/1172005thinh/AutoInstaller) (MIT):
nhánh `main` (commit `a9005a1`, 09/10/2026) và nhánh `dev` (v0.1.2, commit `ec6483f`, 08/09/2026). Ghi lại đây để biết
vì sao AutoSetup_Win giữ cái gì, bỏ cái gì.

## Repo gốc làm gì

USB Ventoy + `autounattend.xml` (sinh từ schneegans.de) cài Windows 11 không cần bấm. Lần đăng nhập đầu, máy tìm phân
vùng phần mềm trên USB bằng file đánh dấu `.md5` rồi chạy `Auto-installer.exe`: cài ứng dụng từ bộ cài để sẵn trên USB
(mỗi ứng dụng một script AutoIt biên dịch ra `.exe`), chỉnh Windows (`configure-windows.ps1`), driver (Snappy Driver
Installer, dự phòng Windows Update), báo cáo.

- **Nhánh `dev`:** chạy được trọn luồng. 12 file unattend chép tay (3 mức × 4 cách chia ổ), 22 ứng dụng offline.
- **Nhánh `main`:** đang làm lại, chưa chạy được. Có GUI AutoIt sinh unattend từ `sample.xml` (xuất ra phân vùng loại
  `Recovery` không hợp lệ), nhiều file 0 byte (`run.au3`, `drivers/`, `confwin/`), khoảng một nửa mini-installer là
  khung hoặc hỏng (tự ghi "AI-assisted, chưa test").

## Giữ lại (ý tưởng)

| Ý tưởng | Trong AutoSetup_Win |
|---|---|
| Ventoy `auto_install`: menu chọn file unattend khi khởi động ISO | `TaoUSB.ps1` thêm mục vào `ventoy.json` |
| Khung unattend theo schneegans: bỏ kiểm tra phần cứng, bỏ OOBE, script nhúng trong XML giải nén ở bước specialize | `unattend/khung.xml`, `unattend/scripts/` |
| Tìm USB bằng thư mục đánh dấu ở lần đăng nhập đầu | `FirstLogon.ps1` tìm `\AutoSetup\sau-cai\SauCai.ps1` |
| Ba mức chạy, nhiều cách chia ổ | 3 cách chia ổ × có/không bước sau cài, **sinh từ một khung** |
| Driver: Windows Update làm dự phòng, khởi động lại rồi chạy tiếp | `Driver.ps1`, tác vụ chạy lại khi đăng nhập |
| Báo cáo cuối | `bao-cao` |

## Bỏ, và làm khác

| Repo gốc | Vấn đề | AutoSetup_Win |
|---|---|---|
| Mặc định (Ventoy tự chọn sau 10 giây) là `full_dyn_C_D`: `WillWipeDisk=true` trên "ổ đầu tiên không phải Ventoy" | Máy hai ổ (SSD + HDD, hai SSD) có thể bị xoá nhầm ổ dữ liệu; ổ USB gắn ngoài cũng tính là "không phải Ventoy" | Mặc định là **chọn ổ tay**. Bản xoá ổ dùng `1ST_NONUSB` và kiểm tra trong WinPE: chỉ xoá khi máy có đúng một ổ trong, UEFI, đủ dung lượng |
| Cài cứng `Windows 11 Pro`, key rỗng | Máy OEM bản Home không tự kích hoạt | Không cài cứng phiên bản: Setup dùng key trong BIOS, không có thì hỏi |
| Tài khoản admin `OEM` **không mật khẩu**, tự đăng nhập, mật khẩu không hết hạn, **bật Remote Desktop** | Dễ bị truy cập | OOBE hỏi tài khoản (mặc định), hoặc tự tạo có mật khẩu; không bật RDP |
| Mỗi ứng dụng một script AutoIt, phải biên dịch; bộ cài tự tải để trên USB; kiểm tra cứng `C:\Program Files` | Bảo trì nặng, phiên bản cũ dần; có nguồn không chính thức (font từ máy chủ riêng, VCRedist bản đóng gói lại); không kiểm mã băm | winget (nguồn Microsoft, kiểm mã băm theo manifest), danh sách trong một file JSON, đọc lại danh sách đã cài để xác nhận |
| 12 file XML gần giống nhau, chép tay | Sửa một chỗ phải sửa 12 chỗ | Một khung + `TaoUnattend.ps1` sinh 6 biến thể, có bài thử |
| Tweak ghi vào HKCU của tài khoản đầu tiên | Tài khoản tạo sau không được áp | Ghi vào hive tài khoản mẫu (`C:\Users\Default\NTUSER.DAT`) ở bước specialize |
| `configure-windows.ps1` tắt **mọi** ứng dụng khởi động cùng Windows (trừ UniKey) | Tắt cả phần mềm người dùng cần | Không làm |
| Theme Ventoy, wallpaper, server font của tác giả | Gắn thương hiệu người khác | Không dùng |
| GUI AutoIt (`main`) | Dở dang, có lỗi | Không làm GUI; cấu hình bằng JSON có kiểm tra |

## Nguồn

- Ventoy auto_install và biến (`$$VT_WINDOWS_DISK_1ST_NONUSB$$`, biến tự đặt được hỏi lúc khởi động):
  https://www.ventoy.net/en/plugin_autoinstall.html
- schneegans unattend-generator: cách nhúng script (`Extensions/ExtractScript`), key BIOS (bỏ `Key`, `WillShowUI`),
  điều kiện chọn ổ an toàn: https://github.com/cschneegans/unattend-generator
