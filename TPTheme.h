#import <UIKit/UIKit.h>

// Trình bày một view controller sau khi hộp thoại/bảng chọn hiện tại đã đóng hẳn.
// Gọi present ngay trong handler của UIAlertAction dễ gây văng app ("presentation in progress"),
// nên mọi chỗ chia sẻ đều đi qua đây.
static inline void TPPresentDelayed(UIViewController *presenter, UIViewController *presented) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [presenter presentViewController:presented animated:YES completion:nil];
    });
}

// Nền ứng dụng tuỳ biến: màu theo hệ thống / đen / 5 màu / ảnh tự chọn.
@interface TPTheme : NSObject

// 0 hệ thống, 1 đen tuyền, 2 ngọc lục bảo, 3 xanh dương, 4 tím, 5 cam, 6 hồng, 7 ảnh tuỳ chọn.
+ (NSInteger)currentMode;
+ (void)setMode:(NSInteger)mode;
+ (NSArray<NSString *> *)modeNames;

+ (void)saveBackgroundImage:(UIImage *)image;
+ (UIImage *)backgroundImage;
+ (void)removeBackgroundImage;

// Áp nền cho một bảng (màu hoặc ảnh + lớp mờ để chữ dễ đọc).
+ (void)applyToTableView:(UITableView *)tableView;
// Hiện/ẩn dòng chữ trạng thái rỗng (vd "Chưa có bản backup nào") tương thích cả chế độ ảnh nền.
+ (void)setEmptyMessage:(NSString *)message forTableView:(UITableView *)tableView;

+ (void)applyTintToWindow:(UIWindow *)window;
+ (void)applyTintToAllWindows;

@end

// Bảng chọn mở một thư mục: Filza / Files / sao chép đường dẫn.
@interface TPOpenFolder : NSObject

+ (void)presentFromViewController:(UIViewController *)viewController path:(NSString *)path anchorView:(UIView *)anchorView;

@end
