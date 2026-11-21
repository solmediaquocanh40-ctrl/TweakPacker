#import "TPSettingsViewController.h"
#import "TPTheme.h"
#import "TPBackupManager.h"
#import "TPFormat.h"
#import "TPLog.h"
#import <PhotosUI/PhotosUI.h>

@interface TPSettingsViewController () <PHPickerViewControllerDelegate>
- (void)pickBackgroundImage;
- (void)shareLog;
@end

@implementation TPSettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Cài đặt";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cài đặt" image:[UIImage systemImageNamed:@"gearshape"] tag:3];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TPTheme applyToTableView:self.tableView];
    [self.tableView reloadData];
}

// section 0: nền (8 chế độ + chọn ảnh + xoá ảnh) / 1: nơi lưu trữ / 2: thông tin
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        NSInteger rows = (NSInteger)[TPTheme modeNames].count + 1; // + "Chọn ảnh từ thư viện…"
        if ([TPTheme backgroundImage]) rows += 1;                  // + "Xoá ảnh nền"
        return rows;
    }
    if (section == 1) return 2;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Nền ứng dụng";
    if (section == 1) return @"Nơi lưu trữ";
    return @"Thông tin & gỡ lỗi";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    NSInteger modeCount = (NSInteger)[TPTheme modeNames].count;
    if (indexPath.section == 0) {
        if (indexPath.row < modeCount) {
            cell.textLabel.text = [TPTheme modeNames][(NSUInteger)indexPath.row];
            if (indexPath.row == 7) {
                cell.detailTextLabel.text = [TPTheme backgroundImage] ? @"Đã có ảnh — bấm để dùng ảnh này làm nền" : @"Chưa chọn ảnh nào";
            }
            cell.accessoryType = ([TPTheme currentMode] == indexPath.row) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else if (indexPath.row == modeCount) {
            cell.textLabel.text = @"Chọn ảnh từ thư viện…";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            cell.textLabel.text = @"Xoá ảnh nền";
            cell.textLabel.textColor = [UIColor systemRedColor];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Thư mục lưu backup";
            cell.detailTextLabel.text = [TPBackupManager backupRoot];
            cell.detailTextLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSArray<TPBackupItem *> *items = [TPBackupManager allItems];
            cell.textLabel.text = @"Mở thư mục lưu trữ";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu bản backup • %@", (unsigned long)items.count, TPSizeString([TPBackupManager totalSizeOfItems:items])];
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Phiên bản TweakPacker";
            cell.detailTextLabel.text = @"1.1.1";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Chia sẻ log gỡ lỗi";
            cell.detailTextLabel.text = TPLogFilePath();
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger modeCount = (NSInteger)[TPTheme modeNames].count;
    if (indexPath.section == 0) {
        if (indexPath.row < modeCount) {
            if (indexPath.row == 7 && ![TPTheme backgroundImage]) {
                [self pickBackgroundImage];
                return;
            }
            [TPTheme setMode:indexPath.row];
            [TPTheme applyTintToAllWindows];
            [TPTheme applyToTableView:self.tableView];
            [self.tableView reloadData];
        } else if (indexPath.row == modeCount) {
            [self pickBackgroundImage];
        } else {
            [TPTheme removeBackgroundImage];
            [TPTheme applyTintToAllWindows];
            [TPTheme applyToTableView:self.tableView];
            [self.tableView reloadData];
        }
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [TPOpenFolder presentFromViewController:self path:[TPBackupManager backupRoot] anchorView:cell];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [self shareLog];
    }
}

- (void)pickBackgroundImage {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    [result.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(__kindof id<NSItemProviderReading> object, NSError *error) {
        if (![object isKindOfClass:[UIImage class]]) return;
        UIImage *image = (UIImage *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            [TPTheme saveBackgroundImage:image];
            [TPTheme setMode:7];
            [TPTheme applyTintToAllWindows];
            [TPTheme applyToTableView:self.tableView];
            [self.tableView reloadData];
        });
    }];
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
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

@end
