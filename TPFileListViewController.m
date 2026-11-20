#import "TPFileListViewController.h"
#import "TPFormat.h"

@interface TPFileListViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@end

@implementation TPFileListViewController

- (instancetype)initWithTitle:(NSString *)title entries:(NSArray<NSDictionary *> *)entries {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = title;
        _entries = [entries copy];
    }
    return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
        cell.textLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.numberOfLines = 2;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"path"] ?: @"";
    NSString *type = entry[@"type"];
    NSNumber *size = entry[@"size"];
    NSString *detail = nil;
    if ([type isEqualToString:@"5"]) {
        detail = @"Thư mục";
    } else if ([type isEqualToString:@"2"]) {
        detail = @"Liên kết (symlink)";
    } else if (size != nil) {
        detail = TPSizeString([size unsignedLongLongValue]);
    }
    cell.detailTextLabel.text = detail;
    return cell;
}

@end
