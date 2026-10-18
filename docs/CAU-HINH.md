# Cấu hình (`cau-hinh/CauHinh.json`)

`TaoUnattend.ps1` và `TaoUSB.ps1` kiểm tra cấu hình trước khi sinh file: khoá sai thì báo rõ khoá nào và dừng.

Muốn đổi vài khoá mà không sửa file chung, tạo `cau-hinh/CauHinh.local.json` (git bỏ qua) chỉ chứa các khoá đó. Đối
tượng được gộp theo từng khoá; mảng thì thay cả mảng. Khoá bắt đầu bằng `_` là ghi chú, bị bỏ qua. Ví dụ:

```json
{
  "_ghiChu": "máy phòng kế toán",
  "tenMay": "hoi",
  "sauCai": { "thuMucCai": "D:\\Program Files" }
}
```

Danh sách ứng dụng riêng: `cau-hinh/UngDung.local.json` (thay cả file `UngDung.json` khi chép lên USB). Cấu hình
Office riêng (Product ID khác, có khoá): `cau-hinh/Office.local.xml` (thay cả file `Office.xml`).

## `ngonNgu`

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `giaoDien` | `en-US` | Ngôn ngữ giao diện Windows. Phải có trong ISO (ISO tiếng Anh: `en-US`) |
| `dinhDang` | `vi-VN` | Định dạng số, ngày, tiền (vi-VN: `1.234,5`, `dd/MM/yyyy`, công thức Excel ngăn tham số bằng `;`). Muốn kiểu `1,234.5` thì để `en-US` |
| `heThong` | `en-US` | Ngôn ngữ cho chương trình không Unicode. Phần mềm cũ dùng font VNI, TCVN3 mà hiện sai chữ thì thử `vi-VN` |
| `banPhim` | `0409:00000409` | Bàn phím (US). Gõ tiếng Việt bằng UniKey, EVKey cài ở bước sau cài |
| `muiGio` | `SE Asia Standard Time` | Múi giờ (UTC+7) |
| `quocGia` | `251` | GeoId (Việt Nam) |

## `banQuyen`

| `cheDo` | Việc |
|---|---|
| `bios` (mặc định) | Không ghi key. Máy có Windows bản quyền OEM (key trong BIOS/UEFI): Setup tự chọn đúng phiên bản và tự kích hoạt. Máy không có key: Setup hỏi key, bấm *I don't have a product key* rồi chọn phiên bản |
| `hoi` | Luôn hiện trang nhập key |
| `key-chung` | Dùng key cài đặt chung của Microsoft cho `phienBanWindows` (`home`, `home_single`, `pro`, `education`, `enterprise`...) để cài thẳng phiên bản đó. Key chung **không kích hoạt** Windows |

## `taiKhoan`

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `cheDo` | `hoi` | `hoi`: OOBE hỏi tên, mật khẩu tài khoản local (không đòi tài khoản Microsoft). `tu-dong`: tự tạo tài khoản quản trị theo `ten`, mật khẩu hỏi lúc chạy `TaoUnattend` (hoặc `-MatKhauFile`, `-KhongMatKhau`) |
| `ten` | `Admin` | Tên tài khoản (chế độ `tu-dong`); 1-20 ký tự **không dấu**, không dùng tên có sẵn như Administrator |
| `tenHienThi` | trống | Tên hiển thị (có dấu được); trống thì bằng `ten`. File unattend chỉ ghi bản bỏ dấu (Windows Setup đổi chữ có dấu thành `?`), lần đăng nhập đầu đặt lại tên có dấu |
| `tuDangNhap` | `true` | Chế độ `tu-dong`: tự đăng nhập lần đầu và tối đa 4 lần khởi động lại của bước sau cài, để nó chạy không cần ai gõ mật khẩu. Xong lượt (hoặc bản không có bước sau cài) thì tắt tự đăng nhập và xoá mật khẩu Windows cất trong LSA |

## `tenMay`

`*` (mặc định): Windows đặt tên ngẫu nhiên. `hoi`: Ventoy hỏi tên máy lúc khởi động USB (biến `$$TEN_MAY$$`), bước sau
cài đổi tên và khởi động lại; gõ trống hoặc sai thì giữ tên ngẫu nhiên. Hoặc một tên cố định (1-15 ký tự chữ, số, dấu
gạch ngang); tên cố định chỉ hợp khi USB dùng cho một máy.

## `oDia` (bản XOÁ SẠCH ổ)

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `heThongMB` | `300` | Phân vùng EFI (MB) |
| `dungLuongC_GB` | `150` | Ổ C ở bản chia C-D; ổ phải có ít nhất C + 20 GB |
| `toiThieuGB` | `60` | Dung lượng ổ tối thiểu ở bản một phân vùng |

## `oobe`

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `hienWifi` | `true` | Hiện trang Wi-Fi trong OOBE (máy xách tay nên bật để bước sau cài có mạng) |
| `boQuaKiemTraPhanCung` | `true` | Bỏ kiểm tra TPM, Secure Boot, RAM, CPU, ổ của Windows 11 |
| `choCaiKhongMang` | `true` | Cho qua OOBE không cần mạng (BypassNRO) |

## `goBo` (gỡ trước khi có tài khoản)

| Khoá | Ý nghĩa |
|---|---|
| `ungDung` | Tên gói Appx cài sẵn cần gỡ (xem tên bằng `Get-AppxProvisionedPackage -Online \| Select DisplayName`). Mặc định chỉ gỡ thứ máy văn phòng gần như không dùng; Calculator, Photos, Notepad, Snipping Tool, Store được giữ |
| `capability` | Capability cần gỡ, ví dụ `App.Support.QuickAssist` (Quick Assist hay bị kẻ gian lợi dụng) |
| `tinhNang` | Tính năng tuỳ chọn cần tắt (mặc định `Recall`) |
| `oneDrive` | `true`: không cài OneDrive cho tài khoản mới |

## `tinhChinh` (áp cho mọi tài khoản)

| Khoá | Mặc định | Việc |
|---|---|---|
| `hienDuoiFile` | `true` | Hiện đuôi file (.docx, .exe) |
| `moThisPC` | `true` | Explorer mở vào This PC |
| `taskbarTrai` | `true` | Nút Start, biểu tượng taskbar căn trái |
| `anTaskView` | `true` | Ẩn nút Task View |
| `timKiem` | `icon` | Ô tìm kiếm trên taskbar: `an`, `icon`, `o` (ô), `nhan` (biểu tượng + chữ) |
| `tatWidgets` | `true` | Tắt Widgets (tin tức, thời tiết) |
| `tatBingTrongStart` | `true` | Tìm trong Start không ra kết quả Bing |
| `tatGoiYUngDung` | `true` | Không tự cài ứng dụng "gợi ý", không hiện gợi ý trong Start, Cài đặt, màn hình khoá |
| `tatCopilot` | `true` | Tắt Copilot (chính sách) |
| `hienEndTask` | `true` | Chuột phải biểu tượng taskbar có *End task* |
| `menuChuotPhaiCu` | `false` | Menu chuột phải kiểu Windows 10 |
| `chanTuMaHoaO` | `true` | Không tự mã hoá ổ bằng BitLocker (tránh khoá ổ khi đổi main, cài lại mà không biết khoá khôi phục) |
| `anEdgeLanDau` | `true` | Bỏ màn hình chào lần đầu của Edge |
| `batDuongDanDai` | `true` | Cho đường dẫn dài hơn 260 ký tự |

## `sauCai`

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `ungDung` | `true` | Cài ứng dụng trong `UngDung.json` |
| `office` | `true` | Cài Office: bộ cài trên USB (`\AutoSetup\office\setup.exe` + `.xml`) nếu có, không thì tải Office Deployment Tool của Microsoft và cài theo `Office.xml` (cần mạng) |
| `driver` | `true` | Driver trên USB và Windows Update |
| `capNhatWindows` | `false` | Cài bản cập nhật Windows (lâu, có thể khởi động lại nhiều lần) |
| `oDuLieuLaD` | `true` | Đưa phân vùng dữ liệu về chữ D |
| `choMangPhut` | `10` | Đợi mạng tối đa bao nhiêu phút ở lần chạy đầu (lần sau 2 phút) |
| `choCaiPhut` | `30` | Mỗi ứng dụng cài quá bao nhiêu phút thì coi là treo: dừng bộ cài, báo lỗi, cài ứng dụng tiếp theo |
| `choODiaPhut` | `5` | Lệnh đọc ổ đĩa của Windows (dò phân vùng ở bước `o-du-lieu`, danh sách ổ và BitLocker trong báo cáo) chạy quá bao nhiêu phút thì dừng. Lệnh này đứng khi Windows không bật được dịch vụ Storage; khởi động lại thường hết, nên bước `o-du-lieu` quá giờ thì khởi động lại máy một lần, sau đó vẫn đứng thì báo lỗi và chạy tiếp các bước sau |
| `thuMucCai` | trống | Thư mục cài riêng (vd `D:\Program Files`) cho ứng dụng có `doiThuMuc: true`; trống là chỗ mặc định |
| `tuKhoiDongLai` | `true` | Cần khởi động lại thì tự khởi động lại sau 60 giây |

## `ventoy`

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `locTenIso` | `(?i)win(dows)?[ ._-]*1[01]` | Biểu thức chọn ISO Windows trên USB để thêm menu cài tự động |
| `choChonGiay` | `15` | Giây chờ chọn trong menu; `0` là chờ mãi |
| `macDinh` | `1` | Mục chọn khi hết giờ (1 = tự chọn ổ, không xoá gì; 0 = cài thường, không dùng file unattend) |

## `UngDung.json`

Mỗi ứng dụng: `khoa` (tên ngắn), `id` (mã gói winget, kiểm bằng `winget show --id <id> -e --source winget`), `ten`,
`macDinh` (`true` là cài), `nhom` (cùng nhóm chỉ cài một, cái đứng trước được ưu tiên: bộ gõ, trình đọc PDF),
`doiThuMuc` (bộ cài nhận được thư mục cài riêng), `loiTat` (ứng dụng portable như UniKey, EVKey: winget chỉ giải nén,
không tạo lối tắt; ghi tên file chạy để bước sau cài tạo lối tắt trong Start), `tuChay` (cùng `loiTat`: thêm lối tắt vào
Startup để chạy cùng Windows, mở luôn sau khi cài), `github` (cùng `loiTat`: `chủ/kho/nhãn/tệp` của bản phát hành
GitHub; winget không cài được thì tải tệp đó, chỉ cài khi SHA256 khớp mã băm GitHub ghi, giải nén vào
`%LOCALAPPDATA%\Programs\<khoa>`. EVKey cần khoá này: tác giả thay `EVKey.zip` trong bản phát hành cũ nên winget báo sai
mã băm), `ghiChu`. Mặc định cài EVKey, UltraViewer, Chrome; các ứng dụng
khác (Zalo, UniKey, 7-Zip, Foxit, Visual C++...) có sẵn trong danh sách, đổi `macDinh` thành `true` để cài.

## `Office.xml`

Cấu hình [Office Deployment Tool](https://learn.microsoft.com/microsoft-365-apps/deploy/office-deployment-tool-configuration-options).
Mặc định: Microsoft 365 Apps (`O365BusinessRetail`) 64-bit, giao diện tiếng Việt kèm tiếng Anh, chỉ Word, Excel,
PowerPoint (các ứng dụng khác nằm trong `ExcludeApp`: xoá dòng của ứng dụng nào thì ứng dụng đó được cài), cài im lặng,
không tự kích hoạt. Kích hoạt bằng đăng nhập tài khoản Microsoft 365 có giấy phép. Office mua đứt hay bản volume: đổi
`Product ID`, `Channel`, thêm `PIDKEY` trong `Office.local.xml`.
