#import <UIKit/UIKit.h>

@class TPBackupItem;

// Chi tiết một bản backup: thông tin + xem file trong .deb + restore (tại máy / qua Sileo) + so sánh + chia sẻ + xoá.
@interface TPBackupItemViewController : UITableViewController

- (instancetype)initWithItem:(TPBackupItem *)item;

@end
