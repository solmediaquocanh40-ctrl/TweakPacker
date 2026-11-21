# TweakPacker 1.1.1

**Backup và khôi phục tweak đã cài — đóng trọn bộ .deb kèm luôn thông số, restore ngay trên máy.**

Chào mọi người, mình là Quoc. TweakPacker là app mình viết cho chính mình trước, vì mình vọc tweak gần như mỗi ngày và gặp đi gặp lại mấy chuyện rất khó chịu: cài thử một tweak, chỉnh thông số tới lui cả buổi mới ưng, hôm sau gỡ ra thử cái khác, tới lúc muốn quay lại thì phải cài lại từ đầu rồi chỉnh lại từ đầu. Có tweak thì repo đóng cửa mất tiêu, file .deb ngày xưa không còn chỗ nào tải lại nữa. IAmLazy trên thị trường cũng làm được chuyện đóng gói lại, nhưng mình muốn một bản của riêng mình: chọn được từng tweak, backup luôn cả thông số đã chỉnh, và quan trọng nhất là khôi phục lại được ngay trong app chứ không phải lọ mọ chép file bằng Filza. Thế là có TweakPacker.

## Có gì mới ở 1.1.1

Bản này là bản vá lỗi theo đúng những gì mình gặp khi dùng 1.1.0 trên máy thật:

- **Hết văng app ở cụm nút "Chọn hết" và nút 3 chấm** — nút 3 chấm giờ mở bảng chọn bình thường, không còn dùng menu kiểu mới hay lỗi nữa. App cũng gắn sẵn bộ ghi lỗi: nếu còn chỗ nào văng, file log sẽ ghi rõ văng ở đâu để mình sửa tiếp, không phải đoán mò.
- **Chia sẻ và "Lưu vào Tệp" hết văng** — bảng chia sẻ giờ được mở sau khi hộp thoại trước đóng hẳn, đúng thứ tự iOS muốn.
- **Tìm prefs kỹ hơn hẳn:** bản trước chỉ tìm file thông số ở một chỗ nên nhiều tweak bị báo thiếu prefs. Giờ app dò cả thư mục Preferences của máy lẫn của jbroot, quét cả tên file gần giống (có tweak đặt domain khác hẳn package ID) và cả thư mục riêng của tweak trong Library. Mỗi file tìm thấy đều ghi rõ đường dẫn gốc, restore là trả về đúng chỗ đó.
- **Mở được đường dẫn nơi lưu:** backup xong có nút "Mở thư mục" ngay trong hộp kết quả; trong Kho backup và trong từng bản backup cũng có chỗ mở thẳng thư mục chứa file — mở bằng Filza, bằng Files, hoặc sao chép đường dẫn.
- **Nền ứng dụng tuỳ biến:** thêm tab Cài đặt với 7 kiểu nền — theo hệ thống, đen tuyền, ngọc lục bảo, xanh dương, tím, cam, hồng — hoặc lấy hẳn một ảnh trong thư viện của bạn làm nền. Màu nhấn của app cũng đổi theo cho đồng bộ.

## Nó làm được gì

- **Danh sách tweak rõ ràng:** mở app lên là thấy toàn bộ gói đã cài trên máy, lọc riêng tweak hoặc xem tất cả, có icon, tên, package ID, phiên bản, tác giả, dung lượng. Tìm kiếm theo tên, package ID hay tác giả đều được, sắp xếp theo tên hoặc theo dung lượng tuỳ ý. Nhấn giữ (hoặc vuốt sang) để xem trang chi tiết của từng tweak: đầy đủ thông tin, có file prefs hay không, xem trước cả danh sách file sẽ được đóng gói.
- **Chọn từng cái hoặc backup tất cả:** chạm để chọn từng tweak (dưới màn hình luôn hiện rõ "Đã chọn: n" nên không bao giờ bấm nhầm trạng thái), hoặc một chạm backup toàn bộ tweak trên máy trước khi vọc vạch gì đó nguy hiểm.
- **Backup kèm thông số (prefs):** đây là phần mình tâm đắc nhất. Mỗi bản backup không chỉ có file .deb chứa trọn bộ dylib, bundle, plist của tweak, mà còn kèm file thông số bạn đã chỉnh trong Cài đặt, kèm một bản ghi (manifest) liệt kê package, phiên bản, đường dẫn gốc của từng file và ngày backup. Restore là trả mọi thứ về đúng chỗ cũ, đúng thông số cũ.
- **Tự kiểm tra sau khi backup:** đóng gói xong app tự mở file .deb ra đọc lại, đếm và đối chiếu với danh sách file gốc rồi báo ngay "đủ X/X file". Thiếu file nào là biết liền tại chỗ, không phải tới lúc cần restore mới phát hiện bản backup hỏng.
- **Kho backup theo từng đợt:** mỗi lần backup tạo một thư mục riêng đặt tên theo ngày giờ, backup bao nhiêu lần cũng không ghi đè bản cũ. Trong tab Kho backup xem được từng bản: phiên bản, ngày giờ, dung lượng, có prefs hay không, đủ file hay thiếu. Các bản .deb lẻ do bản 1.0.0 xuất vẫn hiện trong kho và dùng bình thường.
- **Xem trước khi restore:** bấm vào một bản backup là xem được toàn bộ file nằm trong .deb đó trước khi quyết định khôi phục.
- **Restore 2 đường, tuỳ bạn chọn:** một là restore ngay trên máy — app tự chép file, khôi phục thông số, cập nhật cơ sở dữ liệu gói rồi hỏi respring luôn; hai là đưa file .deb sang Sileo cài như gói bình thường. Trước khi restore tại máy, app kiểm tra trước và nói rõ: thiếu gói phụ thuộc thì nó chặn lại và khuyên đi đường Sileo, gói có script cài đặt thì nó cảnh báo vì restore tại máy không chạy được các script đó, restore bản cũ hơn bản đang cài thì nó nhắc đây là hạ cấp. Mình ghét nhất kiểu app làm xong xuôi rồi mới báo lỗi, nên cái nào có nguy cơ là nó nói trước.
- **Chỉ khôi phục thông số:** nhiều khi tweak còn nguyên, chỉ có thông số bị mình chỉnh hư — khôi phục riêng prefs từ bản backup là xong, không cần đụng tới file tweak.
- **So sánh 2 bản backup:** cùng một tweak backup 2 lần ở 2 thời điểm, app chỉ ra file nào thêm, file nào mất, file nào đổi kích thước, phiên bản nào với nào.
- **Xuất báo cáo tổng hợp:** một file text liệt kê toàn bộ gói đã cài kèm phiên bản và tác giả, gửi cho ai cần xem máy bạn đang có gì cũng tiện.
- **Nhật ký trong app:** mọi lần backup, restore, xoá thành công hay thất bại đều ghi lại trong tab Nhật ký, kèm nút chia sẻ file log gỡ lỗi khi cần nhờ người khác xem giúp.

## Vài lưu ý thật lòng

- Restore tại máy chép file trực tiếp nên **không chạy script cài đặt (postinst...)** của gói. Phần lớn tweak không cần script vẫn chạy bình thường; tweak nào phụ thuộc script thì app đã cảnh báo trước, cứ đi đường Sileo là chắc ăn nhất.
- File prefs được dò theo 3 lớp: domain của tweak (thường trùng package ID, cộng thêm cấu hình đọc từ PreferenceBundle) trong cả hai thư mục Preferences (của máy và của jbroot); quét tên file gần giống cho các tweak đặt domain lạ; và thư mục riêng của tweak trong Library. Tweak nào giấu thông số ở chỗ lạ hơn nữa thì bản ghi sẽ ghi rõ "không tìm thấy prefs" chứ không im lặng, và file log liệt kê mọi đường app đã kiểm để còn biết mà sửa.
- Trước khi ghi vào cơ sở dữ liệu gói, app luôn sao lưu file dpkg status vào thư mục `dpkg-snapshots` trong thư mục TweakPacker, có chuyện gì còn đường lui.
- File backup nằm ở `Documents/TweakPacker` trên máy, mở Filza lên là thấy, chép ra ngoài thoải mái.

## Yêu cầu

- Máy đã jailbreak, iOS 15 trở lên. Bản thân mình dùng Dopamine (rootless) trên iPhone 12 Pro, iOS 16.3.1. Có đủ bản rootful / rootless / roothide.
- Package: `com.anhdang.tweakpacker` — app độc lập, không chích vào SpringBoard, không cần respring khi cài.

## Build từ source

Dự án Theos dạng application. Đẩy source lên GitHub, workflow có sẵn trong `.github/workflows/build.yml` (chạy trên macos-latest, tự cài Theos + ldid) sẽ build cả 3 bản rootful / rootless / roothide. Nhớ: sau khi sửa workflow phải commit mới, bấm Re-run là nó chạy lại workflow cũ đó.

Cảm ơn mọi người đã ghé xem. Ai dùng thấy lỗi hay có ý tưởng gì hay thì cứ góp ý, mình vẫn đang hoàn thiện nó tiếp.

— Quoc
