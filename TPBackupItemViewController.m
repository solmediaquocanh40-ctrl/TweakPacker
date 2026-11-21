#import "TPBackupItemViewController.h"
#import "TPBackupManager.h"
#import "TPRestoreManager.h"
#import "TPDebReader.h"
#import "TPFileListViewController.h"
#import "TPCompareViewController.h"
#import "TPProgressHUD.h"
#import "TPTheme.h"
#import "TPFormat.h"
#import "TPLog.h"

@interface TPBackupItemViewController ()
@property (nonatomic, strong) TPBackupItem *item;
- (NSArray<NSArray<NSString *> *> *)infoRows;
- (NSArray<NSString *> *)actionRows;
- (void)showDebContents;
- (void)askRestoreWay;
- (void)restoreViaSileo;
- (void)restoreInAppFlow;
- (void)performInAppRestore;
- (void)restorePrefsFlow;
- (void)compareFlow;
- (void)shareDeb;
- (void)deleteFlow;
- (void)showOKAlertWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation TPBackupItemViewController

- (instancetype)initWithItem:(TPBackupItem *)item {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _item = item;
        self.title = item.displayName;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TPTheme applyToTableView:self.tableView];
}

- (NSArray<NSArray<NSString *> *> *)infoRows {
    TPBackupItem *item = self.item;
    return @[
        @[@"Tên", item.displayName ?: @""],
        @[@"Package", item.packageID ?: @""],
        @[@"Phiên bản", item.version ?: @""],
        @[@"Tác giả", item.author.length > 0 ? item.author : @"—"],
        @[@"Ngày backup", TPDateTimeString(item.date)],
        @[@"Dung lượng .deb", TPSizeString(item.debSize)],
        @[@"Số file trong .deb", [NSString stringWithFormat:@"%lu", (unsigned long)item.fileCount]],
        @[@"Prefs", item.hasPrefs ? [NSString stringWithFormat:@"Có (%lu file)", (unsigned long)item.prefsBackups.count] : @"Không có"],
        @[@"Kiểm tra toàn vẹn", item.integrityNote ?: @""],
        @[@"Script cài đặt", item.scriptNames.count > 0 ? [item.scriptNames componentsJoinedByString:@", "] : @"Không có"],
        @[@"Phụ thuộc", item.dependsRaw.length > 0 ? item.dependsRaw : @"Không có"],
    ];
}

- (NSArray<NSString *> *)actionRows {
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithObject:@"Xem file trong .deb"];
    [rows addObject:@"Restore tweak này"];
    if (self.item.hasPrefs) [rows addObject:@"Chỉ khôi phục thông số (prefs)"];
    [rows addObject:@"So sánh với bản backup khác"];
    [rows addObject:@"Chia sẻ .deb"];
    [rows addObject:@"Mở thư mục chứa bản này"];
    [rows addObject:@"Xoá bản backup"];
    return [rows copy];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)[self infoRows].count;
    return (NSInteger)[self actionRows].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Thông tin bản backup" : @"Thao tác";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"ItemCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    if (indexPath.section == 0) {
        NSArray<NSString *> *row = [self infoRows][(NSUInteger)indexPath.row];
        cell.textLabel.text = row[0];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.text = row[1];
        cell.detailTextLabel.numberOfLines = 0;
    } else {
        NSString *action = [self actionRows][(NSUInteger)indexPath.row];
        cell.textLabel.text = action;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if ([action hasPrefix:@"Xem file"] || [action hasPrefix:@"So sánh"]) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if ([action hasPrefix:@"Xoá"]) {
            cell.textLabel.textColor = [UIColor systemRedColor];
        } else if ([action hasPrefix:@"Restore"] || [action hasPrefix:@"Chỉ khôi phục"]) {
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    NSString *action = [self actionRows][(NSUInteger)indexPath.row];
    if ([action hasPrefix:@"Xem file"]) [self showDebContents];
    else if ([action hasPrefix:@"Restore tweak"]) [self askRestoreWay];
    else if ([action hasPrefix:@"Chỉ khôi phục"]) [self restorePrefsFlow];
    else if ([action hasPrefix:@"So sánh"]) [self compareFlow];
    else if ([action hasPrefix:@"Chia sẻ"]) [self shareDeb];
    else if ([action hasPrefix:@"Mở thư mục"]) [TPOpenFolder presentFromViewController:self path:[self.item sessionDirectory] anchorView:[tableView cellForRowAtIndexPath:indexPath]];
    else if ([action hasPrefix:@"Xoá"]) [self deleteFlow];
}

#pragma mark - Xem trước .deb

- (void)showDebContents {
    TPBackupItem *item = self.item;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary *> *entries = item.fileList;
        if (entries.count == 0) {
            NSError *error = nil;
            TPDebReader *reader = [TPDebReader readerWithPath:item.debPath error:&error];
            NSMutableArray<NSDictionary *> *parsed = [NSMutableArray array];
            for (TPDebEntry *entry in reader.dataEntries) {
                [parsed addObject:@{ @"path": entry.path, @"size": @(entry.size), @"type": [NSString stringWithFormat:@"%c", entry.type] }];
            }
            entries = [parsed copy];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            TPFileListViewController *vc = [[TPFileListViewController alloc] initWithTitle:@"File trong .deb" entries:entries];
            [self.navigationController pushViewController:vc animated:YES];
        });
    });
}

#pragma mark - Restore

- (void)askRestoreWay {
    TPBackupItem *item = self.item;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Restore %@ %@", item.displayName, item.version] message:@"Restore ngay trên máy: app tự chép file + khôi phục prefs + ghi dpkg (không chạy script cài đặt của gói).\nĐưa sang Sileo: cài bằng Sileo như một gói bình thường, đầy đủ script và phụ thuộc." preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Restore ngay trên máy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self restoreInAppFlow];
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Đưa sang Sileo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self restoreViaSileo];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)restoreViaSileo {
    [TPBackupManager recordHistoryAction:@"Restore qua Sileo" packageID:self.item.packageID ok:YES detail:@"Đã mở bảng chia sẻ .deb"];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:self.item.debPath]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    TPPresentDelayed(self, share);
}

- (void)restoreInAppFlow {
    TPBackupItem *item = self.item;
    NSArray<NSString *> *blocking = [TPRestoreManager blockingProblemsForItem:item];
    if (blocking.count > 0) {
        [self showOKAlertWithTitle:@"Chưa thể restore tại máy" message:[blocking componentsJoinedByString:@"\n"]];
        return;
    }
    NSArray<NSString *> *warnings = [TPRestoreManager warningsForItem:item];
    if (warnings.count == 0) {
        [self performInAppRestore];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lưu ý trước khi restore" message:[warnings componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vẫn restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self performInAppRestore];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performInAppRestore {
    TPBackupItem *item = self.item;
    TPProgressHUD *hud = [TPProgressHUD showInView:self.view title:@"Đang restore…"];
    [hud updateWithStep:@"Đang chuẩn bị…" fraction:-1.0f];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *errorMessage = nil;
        BOOL ok = [TPRestoreManager restoreInApp:item progress:^(NSString *step) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [hud updateWithStep:step fraction:-1.0f];
            });
        } error:&errorMessage];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud dismiss];
            if (!ok) {
                [self showOKAlertWithTitle:@"Restore chưa xong" message:errorMessage ?: @"Lỗi không rõ"];
                return;
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore xong" message:[NSString stringWithFormat:@"Đã khôi phục %@ %@. Cần respring để tweak nạp lại bản vừa restore.", item.displayName, item.version] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Để sau" style:UIAlertActionStyleDefault handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Respring ngay" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if (![TPRestoreManager attemptRespring]) {
                    [self showOKAlertWithTitle:@"Chưa respring tự động được" message:@"App không gửi được lệnh respring trên máy này — anh respring bằng app Dopamine hoặc trong Control Center giúp em nhé."];
                }
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)restorePrefsFlow {
    TPBackupItem *item = self.item;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Khôi phục thông số" message:@"Thông số hiện tại của tweak sẽ bị ghi đè bằng thông số trong bản backup này. Tiếp tục?" preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Khôi phục" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *errorMessage = nil;
        BOOL ok = [TPRestoreManager restorePrefsOnly:item error:&errorMessage];
        [self showOKAlertWithTitle:ok ? @"Đã khôi phục thông số" : @"Khôi phục chưa xong"
                           message:ok ? @"Xong. Respring để tweak nhận lại thông số." : (errorMessage ?: @"Lỗi không rõ")];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - So sánh / chia sẻ / xoá

- (void)compareFlow {
    TPBackupItem *item = self.item;
    NSMutableArray<TPBackupItem *> *others = [NSMutableArray array];
    for (TPBackupItem *other in [TPBackupManager allItems]) {
        if ([other.packageID isEqualToString:item.packageID] && ![other.debPath isEqualToString:item.debPath]) {
            [others addObject:other];
        }
    }
    if (others.count == 0) {
        [self showOKAlertWithTitle:@"Chưa so sánh được" message:@"Tweak này mới có một bản backup duy nhất trong kho."];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"So sánh với bản…" message:[NSString stringWithFormat:@"Bản hiện tại: %@ (%@)", item.version, TPDateTimeString(item.date)] preferredStyle:UIAlertControllerStyleActionSheet];
    for (TPBackupItem *other in others) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ — %@", other.version, TPDateTimeString(other.date)] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            TPCompareViewController *vc = [[TPCompareViewController alloc] initWithItemA:item itemB:other];
            [self.navigationController pushViewController:vc animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareDeb {
    [self restoreViaSileo];
}

- (void)deleteFlow {
    TPBackupItem *item = self.item;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xoá bản backup" message:[NSString stringWithFormat:@"Xoá bản backup %@ %@? File .deb và prefs kèm theo sẽ bị xoá hẳn.", item.displayName, item.version] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Xoá" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *errorMessage = nil;
        if ([TPBackupManager deleteItem:item error:&errorMessage]) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            [self showOKAlertWithTitle:@"Xoá chưa xong" message:errorMessage ?: @"Lỗi không rõ"];
        }
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)showOKAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
