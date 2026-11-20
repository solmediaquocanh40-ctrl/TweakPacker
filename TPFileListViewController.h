#import <UIKit/UIKit.h>

// Danh sách file đơn giản: mỗi mục là {path, size (NSNumber, tuỳ chọn), type ("0"/"5"/"2", tuỳ chọn)}.
@interface TPFileListViewController : UITableViewController

- (instancetype)initWithTitle:(NSString *)title entries:(NSArray<NSDictionary *> *)entries;

@end
