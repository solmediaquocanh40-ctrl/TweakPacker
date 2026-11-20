#import <UIKit/UIKit.h>

@class TPBackupItem;

// So sánh 2 bản backup của cùng một tweak: file thêm / mất / đổi kích thước + phiên bản.
@interface TPCompareViewController : UITableViewController

- (instancetype)initWithItemA:(TPBackupItem *)a itemB:(TPBackupItem *)b;

@end
