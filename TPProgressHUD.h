#import <UIKit/UIKit.h>

// Lớp phủ tiến trình dùng khi backup/restore: thẻ ở giữa màn hình, có dòng bước hiện tại + thanh %.
@interface TPProgressHUD : UIView

+ (instancetype)showInView:(UIView *)view title:(NSString *)title;

// fraction < 0 nghĩa là chưa đo được % — hiện vòng quay thay cho thanh tiến trình.
- (void)updateWithStep:(NSString *)step fraction:(float)fraction;
- (void)dismiss;

@end
