#import "TPPackageListViewController.h"
#import "TPDpkg.h"
#import "TPDebBuilder.h"
#import "TPBackupManager.h"
#import "TPDetailViewController.h"
#import "TPProgressHUD.h"
#import "TPFormat.h"
#import "TPLog.h"

@interface TPPackageListViewController ()

@property (nonatomic, strong) NSArray<TPPackage *> *allPackages;
@property (nonatomic, strong) NSArray<TPPackage *> *visiblePackages;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIDs;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UIBarButtonItem *exportItem;
@property (nonatomic, strong) UIBarButtonItem *selectItem;
@property (nonatomic, strong) UIBarButtonItem *menuItem;
@property (nonatomic, strong) UIBarButtonItem *countItem;
@property (nonatomic, strong) UIBarButtonItem *clearItem;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, assign) BOOL showAll;
@property (nonatomic, assign) NSInteger sortMode; // 0 = theo tên, 1 = theo dung lượng

- (void)rebuildVisible;
- (void)updateSelectionUI;
- (void)clearSelection;
- (void)toggleSelectVisible;
- (void)showBackupResultWithItems:(NSArray<TPBackupItem *> *)items failures:(NSArray<NSString *> *)failures sessionName:(NSString *)sessionName;
- (void)backupSelected;
- (void)backupAllTweaks;
- (void)exportReport;
- (void)runBackupWithPackages:(NSArray<TPPackage *> *)targets;
- (void)scopeChanged:(UISegmentedControl *)sender;
- (UIMenu *)buildMenu;
- (UIImage *)thumbnailForPackage:(TPPackage *)package;
- (void)showDetailForPackage:(TPPackage *)package;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;

@end

@implementation TPPackageListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TweakPacker";
    self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Đã cài" image:[UIImage systemImageNamed:@"list.bullet"] tag:0];
    self.allPackages = @[];
    self.visiblePackages = @[];
    self.selectedIDs = [NSMutableSet set];
    self.showAll = NO;
    self.sortMode = 0;
    self.iconCache = [[NSCache alloc] init];

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Tweak", @"Tất cả"]];
    self.scopeControl.selectedSegmentIndex = 0;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.scopeControl;

    self.selectItem = [[UIBarButtonItem alloc] initWithTitle:@"Chọn hết" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectVisible)];
    self.menuItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:nil action:nil];
    self.menuItem.menu = [self buildMenu];
    self.navigationItem.leftBarButtonItems = @[self.selectItem, self.menuItem];

    self.exportItem = [[UIBarButtonItem alloc] initWithTitle:@"Backup" style:UIBarButtonItemStyleDone target:self action:@selector(backupSelected)];
    self.navigationItem.rightBarButtonItem = self.exportItem;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm tên / package / tác giả";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    // Thanh dưới cùng: luôn hiện rõ "Đã chọn: n" để không bao giờ mơ hồ trạng thái chọn.
    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.font = [UIFont systemFontOfSize:13];
    countLabel.textColor = [UIColor secondaryLabelColor];
    self.countItem = [[UIBarButtonItem alloc] initWithCustomView:countLabel];
    self.clearItem = [[UIBarButtonItem alloc] initWithTitle:@"Bỏ chọn" style:UIBarButtonItemStylePlain target:self action:@selector(clearSelection)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[flex, self.countItem, flex, self.clearItem];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:longPress];

    [self rebuildVisible];
    [self updateSelectionUI];
    TPLog(@"TweakPacker mo len. Tien to jb: '%@'", [TPDpkg jbPrefix]);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<TPPackage *> *packages = [TPDpkg installedPackages];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allPackages = packages;
            [self rebuildVisible];
        });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.toolbarHidden = YES;
}

- (void)clearSelection {
    [self.selectedIDs removeAllObjects];
    [self.tableView reloadData];
    [self updateSelectionUI];
}

#pragma mark - Menu

- (UIMenu *)buildMenu {
    UIAction *sortName = [UIAction actionWithTitle:@"Sắp xếp theo tên" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        self.sortMode = 0;
        self.menuItem.menu = [self buildMenu];
        [self rebuildVisible];
    }];
    sortName.state = self.sortMode == 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *sortSize = [UIAction actionWithTitle:@"Sắp xếp theo dung lượng" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        self.sortMode = 1;
        self.menuItem.menu = [self buildMenu];
        [self rebuildVisible];
    }];
    sortSize.state = self.sortMode == 1 ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIMenu *sortMenu = [UIMenu menuWithTitle:@"Sắp xếp" children:@[sortName, sortSize]];
    UIAction *backupAll = [UIAction actionWithTitle:@"Backup tất cả tweak" image:[UIImage systemImageNamed:@"archivebox"] identifier:nil handler:^(__kindof UIAction *action) {
        [self backupAllTweaks];
    }];
    UIAction *report = [UIAction actionWithTitle:@"Xuất báo cáo tổng hợp" image:[UIImage systemImageNamed:@"doc.text"] identifier:nil handler:^(__kindof UIAction *action) {
        [self exportReport];
    }];
    return [UIMenu menuWithTitle:@"" children:@[sortMenu, backupAll, report]];
}

#pragma mark - Lọc danh sách

- (void)rebuildVisible {
    NSString *query = self.searchController.searchBar.text.lowercaseString ?: @"";
    NSMutableArray<TPPackage *> *visible = [NSMutableArray array];
    for (TPPackage *pkg in self.allPackages) {
        if (!self.showAll && !pkg.isTweak) continue;
        if (query.length > 0) {
            BOOL match = [pkg.displayName.lowercaseString containsString:query] ||
                         [pkg.packageID.lowercaseString containsString:query] ||
                         [pkg.author.lowercaseString containsString:query];
            if (!match) continue;
        }
        [visible addObject:pkg];
    }
    if (self.sortMode == 1) {
        [visible sortUsingComparator:^NSComparisonResult(TPPackage *a, TPPackage *b) {
            if (a.totalSize != b.totalSize) return a.totalSize > b.totalSize ? NSOrderedAscending : NSOrderedDescending;
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];
    } else {
        [visible sortUsingComparator:^NSComparisonResult(TPPackage *a, TPPackage *b) {
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];
    }
    self.visiblePackages = [visible copy];
    [self.tableView reloadData];
    if (self.visiblePackages.count == 0) {
        UILabel *label = [[UILabel alloc] init];
        label.text = self.allPackages.count == 0 ? @"Đang đọc danh sách gói…" : @"Không có gói nào khớp";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        self.tableView.backgroundView = label;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildVisible];
}

- (void)scopeChanged:(UISegmentedControl *)sender {
    self.showAll = (sender.selectedSegmentIndex == 1);
    [self rebuildVisible];
}

#pragma mark - Chọn gói

- (void)updateSelectionUI {
    NSUInteger n = self.selectedIDs.count;
    self.exportItem.title = n > 0 ? [NSString stringWithFormat:@"Backup (%lu)", (unsigned long)n] : @"Backup";
    self.exportItem.enabled = n > 0;
    UILabel *label = (UILabel *)self.countItem.customView;
    label.text = [NSString stringWithFormat:@"Đã chọn: %lu", (unsigned long)n];
    [label sizeToFit];
    self.clearItem.enabled = n > 0;
}

- (void)toggleSelectVisible {
    BOOL allSelected = self.visiblePackages.count > 0;
    for (TPPackage *pkg in self.visiblePackages) {
        if (![self.selectedIDs containsObject:pkg.packageID]) {
            allSelected = NO;
            break;
        }
    }
    for (TPPackage *pkg in self.visiblePackages) {
        if (allSelected) {
            [self.selectedIDs removeObject:pkg.packageID];
        } else {
            [self.selectedIDs addObject:pkg.packageID];
        }
    }
    [self.tableView reloadData];
    [self updateSelectionUI];
}

#pragma mark - Bảng

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.visiblePackages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"PackageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    TPPackage *pkg = self.visiblePackages[(NSUInteger)indexPath.row];
    cell.textLabel.text = pkg.displayName;
    NSString *authorPart = pkg.author.length > 0 ? [NSString stringWithFormat:@"  •  %@", pkg.author] : @"";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@  •  %@%@", pkg.packageID, pkg.version, TPSizeString(pkg.totalSize), authorPart];
    cell.imageView.image = [self thumbnailForPackage:pkg];
    cell.imageView.tintColor = [UIColor systemGrayColor];
    BOOL selected = [self.selectedIDs containsObject:pkg.packageID];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TPPackage *pkg = self.visiblePackages[(NSUInteger)indexPath.row];
    if ([self.selectedIDs containsObject:pkg.packageID]) {
        [self.selectedIDs removeObject:pkg.packageID];
    } else {
        [self.selectedIDs addObject:pkg.packageID];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateSelectionUI];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    TPPackage *pkg = self.visiblePackages[(NSUInteger)indexPath.row];
    UIContextualAction *detail = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Chi tiết" handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        [self showDetailForPackage:pkg];
        completion(YES);
    }];
    detail.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[detail]];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return;
    [self showDetailForPackage:self.visiblePackages[(NSUInteger)indexPath.row]];
}

- (void)showDetailForPackage:(TPPackage *)package {
    TPDetailViewController *vc = [[TPDetailViewController alloc] initWithPackage:package];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UIImage *)thumbnailForPackage:(TPPackage *)package {
    UIImage *cached = [self.iconCache objectForKey:package.packageID];
    if (cached) return cached;
    UIImage *image = nil;
    NSString *iconPath = [TPDpkg iconPathForPackage:package];
    if (iconPath) {
        UIImage *raw = [UIImage imageWithContentsOfFile:iconPath];
        if (raw) {
            CGFloat side = 29.0;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
            image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [raw drawInRect:CGRectMake(0, 0, side, side)];
            }];
        }
    }
    if (!image) {
        image = [[UIImage systemImageNamed:@"puzzlepiece.extension.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        // Ảnh mẫu dùng chung, tô màu tại cell bằng tintColor của imageView là đủ — trả về ảnh hệ thống.
    }
    if (image) [self.iconCache setObject:image forKey:package.packageID];
    return image;
}

#pragma mark - Backup

- (void)backupSelected {
    NSMutableArray<TPPackage *> *targets = [NSMutableArray array];
    for (TPPackage *pkg in self.allPackages) {
        if ([self.selectedIDs containsObject:pkg.packageID]) [targets addObject:pkg];
    }
    if (targets.count == 0) return;
    [self runBackupWithPackages:[targets copy]];
}

- (void)backupAllTweaks {
    NSMutableArray<TPPackage *> *targets = [NSMutableArray array];
    for (TPPackage *pkg in self.allPackages) {
        if (pkg.isTweak) [targets addObject:pkg];
    }
    if (targets.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chưa có tweak nào" message:@"Danh sách chưa đọc xong hoặc máy chưa cài tweak nào." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Backup tất cả tweak" message:[NSString stringWithFormat:@"Sẽ backup toàn bộ %lu tweak vào một đợt mới trong kho. Tiếp tục?", (unsigned long)targets.count] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self runBackupWithPackages:[targets copy]];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)runBackupWithPackages:(NSArray<TPPackage *> *)targets {
    TPProgressHUD *hud = [TPProgressHUD showInView:self.view title:@"Đang backup…"];
    [hud updateWithStep:@"Đang chuẩn bị…" fraction:0.0f];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *session = [TPBackupManager createSessionDirectory];
        NSMutableArray<TPBackupItem *> *items = [NSMutableArray array];
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        NSUInteger index = 0;
        for (TPPackage *pkg in targets) {
            NSUInteger current = index;
            NSString *errorMessage = nil;
            TPBackupItem *item = [TPBackupManager backupPackage:pkg intoSession:session progress:^(NSString *step, float fraction) {
                float overall = ((float)current + fraction) / (float)targets.count;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [hud updateWithStep:[NSString stringWithFormat:@"%@ (%lu/%lu)\n%@", pkg.displayName, (unsigned long)(current + 1), (unsigned long)targets.count, step] fraction:overall];
                });
            } error:&errorMessage];
            if (item) {
                [items addObject:item];
            } else {
                [failures addObject:[NSString stringWithFormat:@"%@: %@", pkg.packageID, errorMessage ?: @"lỗi không rõ"]];
            }
            index++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud dismiss];
            [self showBackupResultWithItems:[items copy] failures:[failures copy] sessionName:session.lastPathComponent];
        });
    });
}

- (void)showBackupResultWithItems:(NSArray<TPBackupItem *> *)items failures:(NSArray<NSString *> *)failures sessionName:(NSString *)sessionName {
    NSMutableString *message = [NSMutableString string];
    if (items.count > 0) {
        [message appendFormat:@"Đã backup %lu tweak vào đợt %@.\n", (unsigned long)items.count, sessionName];
        for (TPBackupItem *item in items) {
            [message appendFormat:@"\n%@ %@ — %@%@", item.integrityOK ? @"✓" : @"⚠", item.displayName, item.integrityNote, item.hasPrefs ? @", có prefs" : @""];
        }
    }
    if (failures.count > 0) {
        [message appendFormat:@"%@Thất bại %lu gói:\n%@", items.count > 0 ? @"\n" : @"", (unsigned long)failures.count, [failures componentsJoinedByString:@"\n"]];
    }
    if (message.length == 0) [message appendString:@"Không backup được gói nào."];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kết quả backup" message:[message copy] preferredStyle:UIAlertControllerStyleAlert];
    if (items.count > 0) {
        UIAlertAction *share = [UIAlertAction actionWithTitle:@"Chia sẻ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *sessionDir = [[TPBackupManager backupRoot] stringByAppendingPathComponent:sessionName];
            NSMutableArray<NSURL *> *urls = [NSMutableArray array];
            for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sessionDir error:nil] ?: @[]) {
                [urls addObject:[NSURL fileURLWithPath:[sessionDir stringByAppendingPathComponent:file]]];
            }
            UIActivityViewController *shareVC = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
            shareVC.popoverPresentationController.sourceView = self.view;
            shareVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
            [self presentViewController:shareVC animated:YES completion:nil];
        }];
        [alert addAction:share];
        alert.preferredAction = share;
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Báo cáo tổng hợp

- (void)exportReport {
    NSMutableString *text = [NSMutableString string];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm dd/MM/yyyy";
    [text appendFormat:@"TweakPacker — Danh sách gói đã cài\nXuất lúc: %@\nTổng: %lu gói\n\n", [formatter stringFromDate:[NSDate date]], (unsigned long)self.allPackages.count];
    for (TPPackage *pkg in self.allPackages) {
        [text appendFormat:@"• %@ (%@) — %@%@\n", pkg.displayName, pkg.packageID, pkg.version, pkg.author.length > 0 ? [NSString stringWithFormat:@" — %@", pkg.author] : @""];
    }
    NSDateFormatter *fileFormatter = [[NSDateFormatter alloc] init];
    fileFormatter.dateFormat = @"yyyyMMdd-HHmmss";
    fileFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *fileName = [NSString stringWithFormat:@"TweakList-%@.txt", [fileFormatter stringFromDate:[NSDate date]]];
    NSString *path = [[TPBackupManager backupRoot] stringByAppendingPathComponent:fileName];
    NSError *error = nil;
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xuất báo cáo thất bại" message:error.localizedDescription ?: @"Lỗi không rõ" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [TPBackupManager recordHistoryAction:@"Xuất báo cáo" packageID:@"" ok:YES detail:fileName];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

@end
