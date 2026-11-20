#import "TPCompareViewController.h"
#import "TPBackupManager.h"
#import "TPFormat.h"

@interface TPCompareViewController ()
@property (nonatomic, strong) TPBackupItem *itemA;
@property (nonatomic, strong) TPBackupItem *itemB;
@property (nonatomic, copy) NSArray<NSString *> *added;
@property (nonatomic, copy) NSArray<NSString *> *removed;
@property (nonatomic, copy) NSArray<NSDictionary *> *changed;
- (NSArray<NSNumber *> *)visibleSections;
@end

@implementation TPCompareViewController

- (instancetype)initWithItemA:(TPBackupItem *)a itemB:(TPBackupItem *)b {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _itemA = a;
        _itemB = b;
        self.title = @"So sánh 2 bản";
        NSDictionary *diff = [TPBackupManager compareItem:a withItem:b];
        _added = diff[@"added"] ?: @[];
        _removed = diff[@"removed"] ?: @[];
        _changed = diff[@"changed"] ?: @[];
    }
    return self;
}

// section 0 = tổng quan; 1 = chỉ có ở B; 2 = chỉ có ở A; 3 = khác kích thước. Mục rỗng thì ẩn.
- (NSArray<NSNumber *> *)visibleSections {
    NSMutableArray<NSNumber *> *sections = [NSMutableArray arrayWithObject:@0];
    if (self.added.count > 0) [sections addObject:@1];
    if (self.removed.count > 0) [sections addObject:@2];
    if (self.changed.count > 0) [sections addObject:@3];
    return [sections copy];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self visibleSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger kind = [self visibleSections][(NSUInteger)section].integerValue;
    if (kind == 0) return 4;
    if (kind == 1) return (NSInteger)self.added.count;
    if (kind == 2) return (NSInteger)self.removed.count;
    return (NSInteger)self.changed.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSInteger kind = [self visibleSections][(NSUInteger)section].integerValue;
    if (kind == 0) return @"Tổng quan";
    if (kind == 1) return [NSString stringWithFormat:@"Chỉ có ở bản B (%lu)", (unsigned long)self.added.count];
    if (kind == 2) return [NSString stringWithFormat:@"Chỉ có ở bản A (%lu)", (unsigned long)self.removed.count];
    return [NSString stringWithFormat:@"Khác kích thước (%lu)", (unsigned long)self.changed.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;
    return [NSString stringWithFormat:@"Bản A: %@ — %@\nBản B: %@ — %@", self.itemA.version, TPDateTimeString(self.itemA.date), self.itemB.version, TPDateTimeString(self.itemB.date)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"CompareCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    NSInteger kind = [self visibleSections][(NSUInteger)indexPath.section].integerValue;
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.numberOfLines = 2;
    if (kind == 0) {
        NSArray<NSArray<NSString *> *> *rows = @[
            @[@"Phiên bản", [NSString stringWithFormat:@"%@ → %@", self.itemA.version, self.itemB.version]],
            @[@"Số file", [NSString stringWithFormat:@"%lu → %lu", (unsigned long)self.itemA.fileCount, (unsigned long)self.itemB.fileCount]],
            @[@"Dung lượng .deb", [NSString stringWithFormat:@"%@ → %@", TPSizeString(self.itemA.debSize), TPSizeString(self.itemB.debSize)]],
            @[@"Kết luận", (self.added.count == 0 && self.removed.count == 0 && self.changed.count == 0) ? @"Hai bản giống hệt nhau về danh sách file" : @"Hai bản có khác nhau, chi tiết bên dưới"],
        ];
        cell.textLabel.text = rows[(NSUInteger)indexPath.row][0];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.text = rows[(NSUInteger)indexPath.row][1];
        cell.detailTextLabel.numberOfLines = 0;
    } else if (kind == 1) {
        cell.textLabel.text = self.added[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = nil;
    } else if (kind == 2) {
        cell.textLabel.text = self.removed[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = nil;
    } else {
        NSDictionary *change = self.changed[(NSUInteger)indexPath.row];
        cell.textLabel.text = change[@"path"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ → %@", TPSizeString([change[@"sizeA"] unsignedLongLongValue]), TPSizeString([change[@"sizeB"] unsignedLongLongValue])];
    }
    return cell;
}

@end
