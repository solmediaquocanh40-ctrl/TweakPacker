# TweakPacker 1.0.0

App riêng (com.anhdang.tweakpacker) cho máy đã jailbreak: xuất bản backup **.deb** cho từng tweak đã cài.

## Tính năng
- Liệt kê các gói đã cài đọc từ cơ sở dữ liệu dpkg; mặc định chỉ hiện tweak, chuyển tab "Tất cả" để xem mọi gói.
- Tìm kiếm theo tên / package ID, **tick chọn riêng từng tweak** (hoặc "Chọn hết" theo danh sách đang hiện).
- Mỗi tweak được đóng thành một file `.deb` **cài lại được**, gom trọn bộ file gói đã đăng ký khi cài: dylib + plist filter, .bundle Cài đặt, plist PreferenceLoader, file layout... kèm cả script preinst/postinst/prerm/postrm và conffiles nếu gói gốc có.
- File xuất ra nằm ở `Documents/TweakPacker/`, bấm **Chia sẻ** để gửi đi ngay (AirDrop, Zalo, Messenger...).
- Tự nhận diện rootful / rootless / roothide. Có log gỡ lỗi ở `Documents/TweakPacker.log`.
- Không chích vào SpringBoard hay bất kỳ tiến trình nào — chỉ đọc dữ liệu gói và ghi file .deb, an toàn cho hệ thống.

## Giới hạn đã biết
- File do tweak tự sinh ra sau khi cài (log, cấu hình tự ghi) không nằm trong danh sách đăng ký của gói nên không được gom.
- Symlink có đích dài hơn 100 ký tự sẽ bị bỏ qua (có ghi trong log).

## Build
Đẩy toàn bộ cây source lên GitHub, kèm file workflow vào `.github/workflows/build.yml` → Actions build 3 bản rootful / rootless / roothide (macos-latest). Máy Quoc (Dopamine) dùng bản **rootless**.
