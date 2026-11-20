#import "TPBackupListViewController.h"
#import "TPBackupManager.h"
#import "TPBackupItemViewController.h"
#import "TPFormat.h"

@interface TPBackupListViewController ()
@property (nonatomic, copy) NSArray<NSArray<TPBackupItem *> *> *sections;
@property (nonatomic, copy) NSArray<TPBackupItem *> *allItems;
- (void)reload;
- (NSString *)headerTitleForSection:(NSInteger)section;
@end

@implementation TPBackupListViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Kho backup";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Kho backup" image:[UIImage systemImageNamed:@"archivebox"] tag:1];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    NSArray<TPBackupItem *> *items = [TPBackupManager allItems];
    self.allItems = items;
    NSMutableArray<NSArray<TPBackupItem *> *> *sections = [NSMutableArray array];
    NSMutableArray<TPBackupItem *> *current = nil;
    NSString *currentKey = nil;
    for (TPBackupItem *item in items) {
        NSString *key = item.legacy ? @"__legacy__" : item.sessionName;
        if (current == nil || ![key isEqualToString:currentKey]) {
            current = [NSMutableArray array];
            currentKey = key;
            [sections addObject:current];
        }
        [current addObject:item];
    }
    NSMutableArray<NSArray<TPBackupItem *> *> *frozen = [NSMutableArray array];
    for (NSMutableArray<TPBackupItem *> *section in sections) {
        [frozen addObject:[section copy]];
    }
    self.sections = [frozen copy];

    if (items.count == 0) {
        UILabel *label = [[UILabel alloc] init];
        label.text = @"Chưa có bản backup nào.\nSang tab Đã cài, chọn tweak rồi bấm Backup.";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        self.tableView.backgroundView = label;
        self.tableView.tableHeaderView = nil;
    } else {
        self.tableView.backgroundView = nil;
        UILabel *summary = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
        summary.text = [NSString stringWithFormat:@"Tổng cộng: %lu bản backup • %@", (unsigned long)items.count, TPSizeString([TPBackupManager totalSizeOfItems:items])];
        summary.textAlignment = NSTextAlignmentCenter;
        summary.font = [UIFont systemFontOfSize:13];
        summary.textColor = [UIColor secondaryLabelColor];
        self.tableView.tableHeaderView = summary;
    }
    [self.tableView reloadData];
}

- (NSString *)headerTitleForSection:(NSInteger)section {
    NSArray<TPBackupItem *> *items = self.sections[(NSUInteger)section];
    TPBackupItem *first = items.firstObject;
    unsigned long long size = [TPBackupManager totalSizeOfItems:items];
    if (first.legacy) {
        return [NSString stringWithFormat:@"Bản lẻ (TweakPacker 1.0.0) • %lu bản • %@", (unsigned long)items.count, TPSizeString(size)];
    }
    return [NSString stringWithFormat:@"Đợt %@ • %lu bản • %@", TPDateTimeString(first.date), (unsigned long)items.count, TPSizeString(size)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self headerTitleForSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"BackupCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    TPBackupItem *item = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    cell.textLabel.text = item.displayName;
    NSMutableString *detail = [NSMutableString stringWithFormat:@"%@  •  %@", item.version, TPSizeString(item.debSize)];
    if (item.hasPrefs) [detail appendString:@"  •  có prefs"];
    if (!item.legacy) [detail appendString:item.integrityOK ? @"  •  ✓ đủ file" : @"  •  ⚠ thiếu file"];
    cell.detailTextLabel.text = [detail copy];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TPBackupItem *item = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    TPBackupItemViewController *vc = [[TPBackupItemViewController alloc] initWithItem:item];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    TPBackupItem *item = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Xoá" handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xoá bản backup" message:[NSString stringWithFormat:@"Xoá bản backup %@ %@? File .deb và prefs kèm theo sẽ bị xoá hẳn.", item.displayName, item.version] preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { completion(NO); }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Xoá" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            NSString *errorMessage = nil;
            [TPBackupManager deleteItem:item error:&errorMessage];
            [self reload];
            completion(YES);
        }]];
        [self presentViewController:confirm animated:YES completion:nil];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end
