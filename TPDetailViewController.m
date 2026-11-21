#import "TPDetailViewController.h"
#import "TPDpkg.h"
#import "TPBackupManager.h"
#import "TPFileListViewController.h"
#import "TPProgressHUD.h"
#import "TPTheme.h"
#import "TPFormat.h"
#import "TPLog.h"

@interface TPDetailViewController ()
@property (nonatomic, strong) TPPackage *package;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *foundPrefs;
- (NSArray<NSArray<NSString *> *> *)infoRows;
- (void)backupThisPackage;
- (void)showFileList;
- (void)shareBackupItem:(TPBackupItem *)item;
@end

@implementation TPDetailViewController

- (instancetype)initWithPackage:(TPPackage *)package {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _package = package;
        self.title = package.displayName;
        _foundPrefs = [TPDpkg prefsFilesForPackage:package];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TPTheme applyToTableView:self.tableView];
}

- (NSArray<NSArray<NSString *> *> *)infoRows {
    TPPackage *pkg = self.package;
    NSString *prefsText;
    if (self.foundPrefs.count > 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSDictionary<NSString *, NSString *> *found in self.foundPrefs) {
            [names addObject:(found[@"source"] ?: @"").lastPathComponent];
        }
        prefsText = [NSString stringWithFormat:@"Có (%lu): %@", (unsigned long)self.foundPrefs.count, [names componentsJoinedByString:@", "]];
    } else {
        prefsText = @"Không thấy file prefs (đã dò thư mục Preferences của máy + jbroot + thư mục riêng của tweak — xem log để biết các đường đã kiểm)";
    }
    return @[
        @[@"Tên", pkg.displayName ?: @""],
        @[@"Package", pkg.packageID ?: @""],
        @[@"Phiên bản", pkg.version ?: @""],
        @[@"Tác giả", pkg.author.length > 0 ? pkg.author : @"—"],
        @[@"Mục", pkg.section.length > 0 ? pkg.section : @"—"],
        @[@"Kiến trúc", pkg.architecture ?: @""],
        @[@"Dung lượng", TPSizeString(pkg.totalSize)],
        @[@"Số file", [NSString stringWithFormat:@"%lu", (unsigned long)pkg.fileCount]],
        @[@"Thông số (prefs)", prefsText],
        @[@"Phụ thuộc", pkg.dependsRaw.length > 0 ? pkg.dependsRaw : @"Không có"],
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)[self infoRows].count;
    if (section == 1) return 1;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Thông tin";
    if (section == 1) return @"Mô tả";
    return @"Thao tác";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"DetailCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        NSArray<NSString *> *row = [self infoRows][(NSUInteger)indexPath.row];
        cell.textLabel.text = row[0];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.text = row[1];
        cell.detailTextLabel.numberOfLines = 0;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = self.package.shortDescription.length > 0 ? self.package.shortDescription : @"—";
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.text = nil;
    } else {
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.text = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Backup tweak này";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"Xem danh sách file (%lu)", (unsigned long)self.package.listedPaths.count];
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;
    if (indexPath.row == 0) {
        [self backupThisPackage];
    } else {
        [self showFileList];
    }
}

- (void)showFileList {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *path in self.package.listedPaths) {
        [entries addObject:@{ @"path": path }];
    }
    TPFileListViewController *vc = [[TPFileListViewController alloc] initWithTitle:@"Danh sách file" entries:[entries copy]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)backupThisPackage {
    TPPackage *package = self.package;
    TPProgressHUD *hud = [TPProgressHUD showInView:self.view title:@"Đang backup…"];
    [hud updateWithStep:package.displayName fraction:0.05f];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *session = [TPBackupManager createSessionDirectory];
        NSString *errorMessage = nil;
        TPBackupItem *item = [TPBackupManager backupPackage:package intoSession:session progress:^(NSString *step, float fraction) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [hud updateWithStep:[NSString stringWithFormat:@"%@\n%@", package.displayName, step] fraction:fraction];
            });
        } error:&errorMessage];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud dismiss];
            if (!item) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup chưa xong" message:errorMessage ?: @"Lỗi không rõ" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            NSString *message = [NSString stringWithFormat:@"Đã backup %@ %@ vào kho.\nKiểm tra: %@\nPrefs: %@", item.displayName, item.version, item.integrityNote, item.hasPrefs ? @"đã backup kèm" : @"không có file prefs"];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kết quả backup" message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *share = [UIAlertAction actionWithTitle:@"Chia sẻ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self shareBackupItem:item];
            }];
            [alert addAction:share];
            alert.preferredAction = share;
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)shareBackupItem:(TPBackupItem *)item {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:item.debPath]];
    NSString *sessionDir = [item sessionDirectory];
    for (NSDictionary<NSString *, NSString *> *prefs in item.prefsBackups) {
        NSString *file = prefs[@"file"];
        if (file.length > 0) [urls addObject:[NSURL fileURLWithPath:[sessionDir stringByAppendingPathComponent:file]]];
    }
    if (!item.legacy) {
        NSString *manifest = [sessionDir stringByAppendingPathComponent:[item.packageID stringByAppendingString:@".manifest.json"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:manifest]) {
            [urls addObject:[NSURL fileURLWithPath:manifest]];
        }
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    TPPresentDelayed(self, share);
}

@end
