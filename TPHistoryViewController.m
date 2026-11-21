#import "TPHistoryViewController.h"
#import "TPBackupManager.h"
#import "TPTheme.h"
#import "TPFormat.h"
#import "TPLog.h"

@interface TPHistoryViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
- (void)reload;
- (void)shareLog;
@end

@implementation TPHistoryViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Nhật ký";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Nhật ký" image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] tag:2];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(shareLog)];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TPTheme applyToTableView:self.tableView];
    [self reload];
}

- (void)reload {
    self.entries = [TPBackupManager historyEntries];
    if (self.entries.count == 0) {
        [TPTheme setEmptyMessage:@"Chưa có hoạt động nào được ghi lại." forTableView:self.tableView];
    } else {
        [TPTheme setEmptyMessage:nil forTableView:self.tableView];
    }
    [self.tableView reloadData];
}

- (void)shareLog {
    NSString *path = TPLogFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chưa có file log" message:@"File log gỡ lỗi chưa được tạo." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"HistoryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.detailTextLabel.numberOfLines = 0;
    }
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    BOOL ok = [entry[@"ok"] boolValue];
    NSString *package = entry[@"package"];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@%@", ok ? @"✓" : @"✗", entry[@"action"] ?: @"", package.length > 0 ? [NSString stringWithFormat:@" — %@", package] : @""];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[entry[@"time"] doubleValue]];
    NSString *detail = entry[@"detail"] ?: @"";
    cell.detailTextLabel.text = detail.length > 0 ? [NSString stringWithFormat:@"%@ • %@", TPDateTimeString(date), detail] : TPDateTimeString(date);
    return cell;
}

@end
