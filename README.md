# AutoSetup_Win

Cài Windows 10/11 tự động từ USB [Ventoy](https://www.ventoy.net): chọn ISO, chọn kiểu cài, rồi để máy tự chạy. Windows
cài xong thì máy tự cài ứng dụng (winget), Office (nếu có bộ cài trên USB), driver, rồi ghi báo cáo.

Dùng cho nhiều máy khác nhau (máy văn phòng, máy khách). Mọi lựa chọn nằm trong một file cấu hình
[`cau-hinh/CauHinh.json`](cau-hinh/CauHinh.json), không cài cứng trong mã. Không cần biên dịch: chỉ PowerShell 5.1 có sẵn
trong Windows.

> **Trạng thái:** bộ bài thử giả lập đạt hết (`tests\CHAY_KIEM_THU.bat`). **Chưa chạy thử một lượt cài Windows thật**
> (máy ảo hoặc máy thật). Thử trên máy ảo trước khi dùng cho máy khách.

## Làm được gì

| Giai đoạn | Việc |
|---|---|
| Khởi động USB | Menu Ventoy cho chọn kiểu cài; mặc định (sau 15 giây) là **tự chọn ổ, không xoá gì** |
| Windows Setup | Bỏ kiểm tra TPM, Secure Boot, RAM, CPU; bỏ qua EULA, màn hình quảng cáo; key lấy từ BIOS (máy có Windows bản quyền OEM tự kích hoạt), máy không có key thì Setup hỏi |
| Trước khi có tài khoản | Gỡ ứng dụng cài sẵn không cần (Clipchamp, Copilot, Bing News, Solitaire, Teams...), bỏ OneDrive, tắt Recall; chặn tự mã hoá BitLocker; chỉnh Explorer, taskbar cho **mọi** tài khoản tạo sau này |
| OOBE | Chỉ còn trang tạo tài khoản local (hoặc tự tạo theo cấu hình) và trang Wi-Fi |
| Lần đăng nhập đầu | Chép bước sau cài từ USB vào `C:\AutoSetup`, chạy: ổ dữ liệu về D, cài ứng dụng (winget), Office, driver (USB + Windows Update), đổi tên máy, báo cáo. Cần khởi động lại thì tự khởi động lại rồi chạy tiếp |

## Dùng nhanh

1. **Cài Ventoy lên USB** (≥ 16 GB) bằng [Ventoy2Disk](https://www.ventoy.net/en/download.html). Chép ISO Windows vào USB
   (ví dụ `\ISO\Win11_26300_x64_en-US.iso`; tên file phải có `win...10` hoặc `win...11`).
2. **Sửa cấu hình** nếu cần: [`cau-hinh/CauHinh.json`](cau-hinh/CauHinh.json) và danh sách ứng dụng
   [`cau-hinh/UngDung.json`](cau-hinh/UngDung.json) (`macDinh: true` là cài). Giải thích từng khoá:
   [docs/CAU-HINH.md](docs/CAU-HINH.md). Muốn giữ cấu hình riêng mà không sửa file chung: tạo `CauHinh.local.json` chỉ
   chứa các khoá cần đổi (git bỏ qua file này).
3. **Bấm đúp `TAO_USB.bat`**: sinh 6 file unattend, chép mọi thứ vào `\AutoSetup` trên USB, thêm menu cài tự động vào
   `\ventoy\ventoy.json` (giữ nguyên cấu hình Ventoy sẵn có, sao lưu bản cũ). Xem trước: `TAO_USB.bat -ChayThu`.
4. (Không bắt buộc) chép bộ cài Office vào `\AutoSetup\office`, driver `.inf` vào `\AutoSetup\drivers` trên USB.
5. Khởi động máy cần cài bằng USB, chọn ISO, chọn kiểu cài trong menu. Cài xong, báo cáo nằm ở
   `C:\AutoSetup\ket_qua` và được chép vào `\AutoSetup\ket_qua` trên USB.

## Menu khi khởi động USB

| Mục | Ổ đĩa | Bước sau cài |
|---|---|---|
| `1_Chon-o-bang-tay` **(mặc định)** | Tự chọn ổ, phân vùng trong Windows Setup. **Không tự xoá gì** | có |
| `2_Chon-o-bang-tay_Chi-Windows` | như trên | không |
| `3_XOA-SACH-o_1-phan-vung` | **Xoá sạch** ổ trong duy nhất, tạo một phân vùng C | có |
| `4_XOA-SACH-o_1-phan-vung_Chi-Windows` | như trên | không |
| `5_XOA-SACH-o_chia-C-D` | **Xoá sạch** ổ, chia C (150 GB, đổi được) và D (phần còn lại) | có |
| `6_XOA-SACH-o_chia-C-D_Chi-Windows` | như trên | không |

"Chỉ Windows" vẫn gỡ ứng dụng cài sẵn và chỉnh Explorer, taskbar như bản đầy đủ, chỉ không chạy bước sau cài từ USB.

## An toàn ổ đĩa

Mục 3-6 xoá sạch ổ. Trước khi Setup chia ổ, một đoạn kiểm tra chạy trong WinPE
([`unattend/KiemTraO.vbs`](unattend/KiemTraO.vbs)) và **chỉ cho xoá khi đủ mọi điều kiện**:

- máy khởi động kiểu UEFI (bản xoá ổ tạo phân vùng GPT);
- máy có **đúng một** ổ trong (không tính USB, thẻ nhớ). Máy có SSD + HDD, hay hai SSD, sẽ bị chặn để không xoá nhầm
  ổ dữ liệu;
- ổ đó đúng là ổ Ventoy chọn (`$$VT_WINDOWS_DISK_1ST_NONUSB$$`: ổ đầu tiên không phải USB, nên không bao giờ là ổ USB
  gắn ngoài);
- ổ đủ dung lượng (60 GB; bản chia C-D cần C + 20 GB).

Sai một điều kiện: hiện thông báo, khởi động lại, không xoá gì. Khi đó chọn mục 1 và tự chọn phân vùng.

## Bước sau cài

Chạy ở lần đăng nhập đầu (tác vụ `\AutoSetup\AutoSetup-TiepTuc`), chạy tiếp sau mỗi lần khởi động lại cho tới khi xong.
Chạy lại bằng tay: `C:\AutoSetup\sau-cai\CHAY_LAI.bat` (`-Chi ung-dung,driver` chỉ chạy vài bước, `-ChayThu` chỉ xem).

| Bước | Việc | Cần mạng |
|---|---|---|
| `o-du-lieu` | Đưa phân vùng dữ liệu về chữ D (lúc cài, USB hay chiếm D). Chỉ đổi khi có đúng một phân vùng dữ liệu, hoặc một phân vùng nhãn DATA | |
| `winget` | Bảo đảm winget chạy được (đăng ký App Installer, cập nhật nguồn) | có |
| `ung-dung` | Cài ứng dụng `macDinh: true` từ nguồn winget của Microsoft; đọc lại danh sách đã cài để chắc đã cài xong; lỗi thì thử lại một lần | có |
| `office` | Cài Office bằng Office Deployment Tool trên USB | khi bộ cài không có sẵn file |
| `driver` | Nạp driver trên USB (`pnputil`), rồi tải driver còn thiếu từ Windows Update; tự khởi động lại, tối đa 3 vòng | Windows Update |
| `cap-nhat-windows` | Cài bản cập nhật Windows (tắt mặc định, lâu) | có |
| `ten-may` | Đổi tên máy theo tên gõ lúc khởi động USB (khi `tenMay: "hoi"`) | |
| `bao-cao` | Báo cáo: máy, bản quyền, từng bước, ứng dụng, ổ đĩa, BitLocker, thiết bị thiếu driver | |

Chưa có mạng thì đợi tối đa `sauCai.choMangPhut` phút (nhắc cắm dây, bắt Wi-Fi), rồi bỏ qua các bước cần mạng; chạy lại
`CHAY_LAI.bat` khi có mạng.

## Office, driver

- **Office:** tải [Office Deployment Tool](https://www.microsoft.com/download/details.aspx?id=49117), chép `setup.exe`
  vào `\AutoSetup\office` trên USB, kèm file cấu hình `cau-hinh.xml` (sửa từ [docs/office-mau.xml](docs/office-mau.xml)
  hoặc tạo ở [config.office.com](https://config.office.com)). Chạy `setup.exe /download cau-hinh.xml` một lần để cài
  không cần mạng. Bộ cài không kèm khoá, không kích hoạt hộ.
- **Driver:** chép thư mục driver dạng `.inf` vào `\AutoSetup\drivers` (ví dụ xuất từ máy cùng model bằng
  `pnputil /export-driver * <thư mục>`). Driver còn thiếu được tải tiếp từ Windows Update.

## Cấu trúc

```
TAO_USB.bat, TAO_UNATTEND.bat   bấm đúp: chép lên USB / chỉ sinh file unattend
cau-hinh/        CauHinh.json (cấu hình), UngDung.json (ứng dụng winget)
unattend/        khung.xml, KiemTraO.vbs (kiểm tra ổ trong WinPE), scripts/ (nhúng vào file unattend:
                 GiaiNen, Specialize, DefaultUser, FirstLogon)
sau-cai/         SauCai.ps1 + lib/ (chép lên USB rồi vào C:\AutoSetup): ứng dụng, driver, ổ đĩa, báo cáo
scripts/         TaoUnattend.ps1, TaoUSB.ps1, ChuanHoaFile.ps1 (chuẩn hoá mã hoá trước khi commit)
tests/           bài thử giả lập: CHAY_KIEM_THU.bat
docs/            CAU-HINH.md, PHAN-TICH-AUTOINSTALLER.md, office-mau.xml
out/             file unattend đã sinh (không commit: có thể có mật khẩu)
```

## Kiểm thử

`tests\CHAY_KIEM_THU.bat` (khoảng 1 phút, không đổi máy, ghi tạm vào `%TEMP%\AutoSetup-KiemThu`). Kiểm: cú pháp và
mã hoá mọi file; cấu hình đúng, sai; 6 file unattend đúng từng biến thể, lệnh WinPE không quá 255 ký tự, mỗi dòng tối đa
một biến Ventoy, script nhúng giải nén ra đúng nội dung; đoạn kiểm tra ổ dựng lại từ đúng các lệnh `echo` trong file
unattend rồi chạy với 13 tình huống ổ đĩa; bước sau cài với winget giả; chép lên USB giả (giữ cấu hình Ventoy cũ).
Sửa file xong thì chạy `scripts\ChuanHoaFile.ps1` (`.ps1` cần BOM để PowerShell 5.1 đọc đúng tiếng Việt).

## Giới hạn

- Bản xoá ổ chỉ cho máy khởi động UEFI, một ổ trong. Máy khác: dùng mục 1.
- Giao diện Windows (`ngonNgu.giaoDien`) phải là ngôn ngữ có trong ISO (ISO tiếng Anh thì để `en-US`).
- Mật khẩu tài khoản tự tạo (`taiKhoan.cheDo: "tu-dong"`) nằm trong file unattend trên USB dạng base64 (che, không mã
  hoá). Windows xoá bản trên máy ở lần đăng nhập đầu; USB thì giữ cẩn thận.
- Không kích hoạt Windows, Office hộ: chỉ dùng key trong BIOS hoặc key/tài khoản của bạn.

## Nguồn tham khảo, giấy phép

- Ý tưởng ban đầu từ [1172005thinh/AutoInstaller](https://github.com/1172005thinh/AutoInstaller) (MIT); phân tích và lý
  do làm khác: [docs/PHAN-TICH-AUTOINSTALLER.md](docs/PHAN-TICH-AUTOINSTALLER.md).
- Cách nhúng, giải nén script trong file unattend, bảng key cài đặt chung: theo
  [cschneegans/unattend-generator](https://github.com/cschneegans/unattend-generator) (MIT).
- [Ventoy auto_install](https://www.ventoy.net/en/plugin_autoinstall.html),
  [Microsoft unattend reference](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/).

Giấy phép MIT, xem [LICENSE](LICENSE).
