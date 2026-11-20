#import <UIKit/UIKit.h>

@class TPPackage;

// Trang chi tiết của một gói đã cài: thông tin đầy đủ + backup riêng lẻ + xem danh sách file.
@interface TPDetailViewController : UITableViewController

- (instancetype)initWithPackage:(TPPackage *)package;

@end
