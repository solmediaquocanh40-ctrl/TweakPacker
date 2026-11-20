#import "TPPackageListViewController.h"
#import "TPDpkg.h"
#import "TPDebBuilder.h"
#import "TPLog.h"

@interface TPPackageListViewController ()

@property (nonatomic, strong) NSArray<TPPackage *> *allPackages;
@property (nonatomic, strong) NSArray<TPPackage *> *visiblePackages;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIDs;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UIBarButtonItem *exportItem;
@property (nonatomic, strong) UIBarButtonItem *selectItem;
@property (nonatomic, assign) BOOL showAll;

- (void)rebuildVisible;
- (void)updateExportButton;
- (void)toggleSelectVisible;
- (void)exportSelected;
- (void)scopeChanged:(UISegmentedControl *)sender;
- (NSString *)sizeStringForPackage:(TPPackage *)package;
- (void)showExportResultWithFiles:(NSArray<NSURL *> *)files failures:(NSArray<NSString *> *)failures;

@end

@implementation TPPackageListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TweakPacker";
    self.allPackages = @[];
    self.visiblePackages = @[];
    self.selectedIDs = [NSMutableSet set];
    self.showAll = NO;

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Tweak", @"Tất cả"]];
    self.scopeControl.selectedSegmentIndex = 0;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.scopeControl;

    self.selectItem = [[UIBarButtonItem alloc] initWithTitle:@"Chọn hết" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectVisible)];
    self.navigationItem.leftBarButtonItem = self.selectItem;

    self.exportItem = [[UIBarButtonItem alloc] initWithTitle:@"Xuất" style:UIBarButtonItemStyleDone target:self action:@selector(exportSelected)];
    self.navigationItem.rightBarButtonItem = self.exportItem;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm tweak / package";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    [self rebuildVisible];
    [self updateExportButton];
    TPLog(@"TweakPacker mo len. Tien to jb: '%@'", [TPDpkg jbPrefix]);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<TPPackage *> *packages = [TPDpkg installedPackages];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allPackages = packages;
            [self rebuildVisible];
        });
    });
}

#pragma mark - Loc danh sach

- (void)rebuildVisible {
    NSString *query = self.searchController.searchBar.text.lowercaseString ?: @"";
    NSMutableArray<TPPackage *> *visible = [NSMutableArray array];
    for (TPPackage *pkg in self.allPackages) {
        if (!self.showAll && !pkg.isTweak) continue;
        if (query.length > 0) {
            BOOL match = [pkg.displayName.lowercaseString containsString:query] || [pkg.packageID.lowercaseString containsString:query];
            if (!match) continue;
        }
        [visible addObject:pkg];
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

#pragma mark - Chon goi

- (void)updateExportButton {
    NSUInteger n = self.selectedIDs.count;
    self.exportItem.title = n > 0 ? [NSString stringWithFormat:@"Xuất (%lu)", (unsigned long)n] : @"Xuất";
    self.exportItem.enabled = n > 0;
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
    [self updateExportButton];
}

#pragma mark - Bang

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
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@  •  %@", pkg.packageID, pkg.version, [self sizeStringForPackage:pkg]];
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
    [self updateExportButton];
}

- (NSString *)sizeStringForPackage:(TPPackage *)package {
    double kb = (double)package.totalSize / 1024.0;
    if (kb < 1024.0) return [NSString stringWithFormat:@"%.0f KB", kb];
    return [NSString stringWithFormat:@"%.1f MB", kb / 1024.0];
}

#pragma mark - Xuat file

- (void)exportSelected {
    NSMutableArray<TPPackage *> *targets = [NSMutableArray array];
    for (TPPackage *pkg in self.allPackages) {
        if ([self.selectedIDs containsObject:pkg.packageID]) [targets addObject:pkg];
    }
    if (targets.count == 0) return;

    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Đang xuất bản backup" message:@"Đang chuẩn bị…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSURL *> *files = [NSMutableArray array];
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        NSUInteger index = 0;
        for (TPPackage *pkg in targets) {
            index++;
            NSUInteger current = index;
            dispatch_async(dispatch_get_main_queue(), ^{
                progress.message = [NSString stringWithFormat:@"%@ (%lu/%lu)", pkg.packageID, (unsigned long)current, (unsigned long)targets.count];
            });
            NSUInteger count = 0;
            NSUInteger skipped = 0;
            NSError *error = nil;
            NSString *path = [TPDebBuilder buildDebForPackage:pkg fileCount:&count skipped:&skipped error:&error];
            if (path) {
                [files addObject:[NSURL fileURLWithPath:path]];
            } else {
                [failures addObject:[NSString stringWithFormat:@"%@: %@", pkg.packageID, error.localizedDescription ?: @"lỗi không rõ"]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:YES completion:^{
                [self showExportResultWithFiles:files failures:failures];
            }];
        });
    });
}

- (void)showExportResultWithFiles:(NSArray<NSURL *> *)files failures:(NSArray<NSString *> *)failures {
    NSString *message = nil;
    if (files.count > 0 && failures.count == 0) {
        message = [NSString stringWithFormat:@"Đã xuất %lu file .deb vào thư mục Documents/TweakPacker.", (unsigned long)files.count];
    } else if (files.count > 0) {
        message = [NSString stringWithFormat:@"Xuất được %lu file. Thất bại %lu gói:\n%@", (unsigned long)files.count, (unsigned long)failures.count, [failures componentsJoinedByString:@"\n"]];
    } else {
        message = [NSString stringWithFormat:@"Không xuất được gói nào:\n%@", [failures componentsJoinedByString:@"\n"]];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kết quả" message:message preferredStyle:UIAlertControllerStyleAlert];
    if (files.count > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Chia sẻ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
            [self presentViewController:share animated:YES completion:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Xong" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
