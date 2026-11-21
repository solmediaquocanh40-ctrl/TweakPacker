#import "TPAppTweakViewController.h"
#import "TPInjectMap.h"
#import "TPFileListViewController.h"
#import "TPTheme.h"
#import "TPLog.h"

@interface TPAppTweakViewController ()

@property (nonatomic, strong) TPInjectMap *map;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) NSInteger mode; // 0 = theo app, 1 = theo tweak
@property (nonatomic, assign) BOOL loading;
// Mỗi mục: @{kind: @"app"|@"system"|@"class"|@"tweak", entry: TPAppInjectEntry (app), tweaks: [...]}
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleSections;

- (void)rescan;
- (void)modeChanged:(UISegmentedControl *)sender;
- (void)rebuildVisible;
- (BOOL)tweak:(TPInjectedTweak *)tweak matchesQuery:(NSString *)query;
- (void)showTweakDetail:(TPInjectedTweak *)tweak;
- (NSString *)subtitleForTweak:(TPInjectedTweak *)tweak;

@end

@implementation TPAppTweakViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = @"App & Tweak";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"App & Tweak" image:[UIImage systemImageNamed:@"puzzlepiece.extension"] tag:4];
        _mode = 0;
        _visibleSections = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Theo app", @"Theo tweak"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.modeControl;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(rescan)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm app hoặc tweak";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    [self rescan];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TPTheme applyToTableView:self.tableView];
}

- (void)rescan {
    self.loading = YES;
    self.map = nil;
    [self rebuildVisible];
    [TPInjectMap buildWithCompletion:^(TPInjectMap *map) {
        self.loading = NO;
        self.map = map;
        [self rebuildVisible];
    }];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    self.mode = sender.selectedSegmentIndex;
    [self rebuildVisible];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildVisible];
}

#pragma mark - Lọc dữ liệu

- (BOOL)tweak:(TPInjectedTweak *)tweak matchesQuery:(NSString *)query {
    if (query.length == 0) return YES;
    if ([tweak.displayName.lowercaseString containsString:query]) return YES;
    if ([tweak.dylibName.lowercaseString containsString:query]) return YES;
    if (tweak.packageID.length > 0 && [tweak.packageID.lowercaseString containsString:query]) return YES;
    for (NSString *target in tweak.targets) {
        if ([target.lowercaseString containsString:query]) return YES;
    }
    return NO;
}

- (void)rebuildVisible {
    NSString *query = self.searchController.searchBar.text.lowercaseString ?: @"";
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    if (self.map) {
        if (self.mode == 0) {
            for (TPAppInjectEntry *entry in self.map.appEntries) {
                BOOL appMatch = query.length == 0 || [entry.name.lowercaseString containsString:query] || [entry.bundleID.lowercaseString containsString:query];
                NSMutableArray<TPInjectedTweak *> *rows = [NSMutableArray array];
                for (TPInjectedTweak *tweak in entry.tweaks) {
                    if (appMatch || [self tweak:tweak matchesQuery:query]) [rows addObject:tweak];
                }
                if (rows.count > 0) {
                    [sections addObject:@{ @"kind": @"app", @"entry": entry, @"tweaks": [rows copy] }];
                }
            }
            NSMutableArray<TPInjectedTweak *> *sys = [NSMutableArray array];
            for (TPInjectedTweak *tweak in self.map.systemWideTweaks) {
                if ([self tweak:tweak matchesQuery:query]) [sys addObject:tweak];
            }
            if (sys.count > 0) [sections addObject:@{ @"kind": @"system", @"tweaks": [sys copy] }];
            NSMutableArray<TPInjectedTweak *> *cls = [NSMutableArray array];
            for (TPInjectedTweak *tweak in self.map.classTweaks) {
                if ([self tweak:tweak matchesQuery:query]) [cls addObject:tweak];
            }
            if (cls.count > 0) [sections addObject:@{ @"kind": @"class", @"tweaks": [cls copy] }];
        } else {
            NSMutableArray<TPInjectedTweak *> *rows = [NSMutableArray array];
            for (TPInjectedTweak *tweak in self.map.allTweaks) {
                if ([self tweak:tweak matchesQuery:query]) [rows addObject:tweak];
            }
            if (rows.count > 0) [sections addObject:@{ @"kind": @"tweak", @"tweaks": [rows copy] }];
        }
    }
    self.visibleSections = [sections copy];

    if (self.loading) {
        [TPTheme setEmptyMessage:@"Đang quét các tweak đã chích…" forTableView:self.tableView];
        self.tableView.tableHeaderView = nil;
    } else if (self.visibleSections.count == 0) {
        [TPTheme setEmptyMessage:query.length > 0 ? @"Không tìm thấy app/tweak nào khớp." : @"Không tìm thấy tweak nào được chích trên máy." forTableView:self.tableView];
        self.tableView.tableHeaderView = nil;
    } else {
        [TPTheme setEmptyMessage:nil forTableView:self.tableView];
        UILabel *summary = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
        summary.text = [NSString stringWithFormat:@"%lu app có tweak • %lu tweak tất cả", (unsigned long)self.map.appEntries.count, (unsigned long)self.map.allTweaks.count];
        summary.textAlignment = NSTextAlignmentCenter;
        summary.font = [UIFont systemFontOfSize:13];
        summary.textColor = [UIColor secondaryLabelColor];
        self.tableView.tableHeaderView = summary;
    }
    [self.tableView reloadData];
}

- (NSString *)subtitleForTweak:(TPInjectedTweak *)tweak {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (tweak.packageID.length > 0) {
        [parts addObject:tweak.packageVersion.length > 0 ? [NSString stringWithFormat:@"%@ • %@", tweak.packageID, tweak.packageVersion] : tweak.packageID];
    } else {
        [parts addObject:[NSString stringWithFormat:@"%@.dylib", tweak.dylibName]];
    }
    if (tweak.embedded) [parts addObject:@"nhúng sẵn trong app"];
    if (tweak.disabled) [parts addObject:@"ĐÃ TẮT"];
    if (self.mode == 1) {
        if (tweak.systemWide) [parts addObject:@"toàn hệ thống"];
        else if (tweak.targets.count > 0) [parts addObject:[tweak.targets componentsJoinedByString:@", "]];
    }
    return [parts componentsJoinedByString:@"  •  "];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.visibleSections[(NSUInteger)section][@"tweaks"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSDictionary *model = self.visibleSections[(NSUInteger)section];
    NSString *kind = model[@"kind"];
    if ([kind isEqualToString:@"system"]) return @"Toàn hệ thống (chích vào mọi app)";
    if ([kind isEqualToString:@"class"]) return @"Theo class (không gắn được vào app cụ thể)";
    if ([kind isEqualToString:@"tweak"]) return @"Tất cả tweak";
    return nil; // section app dùng header tự vẽ
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSDictionary *model = self.visibleSections[(NSUInteger)section];
    return [model[@"kind"] isEqualToString:@"app"] ? 52.0 : UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSDictionary *model = self.visibleSections[(NSUInteger)section];
    if (![model[@"kind"] isEqualToString:@"app"]) return nil;
    TPAppInjectEntry *entry = model[@"entry"];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 52)];
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 10, 32, 32)];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 7;
    iconView.clipsToBounds = YES;
    UIImage *icon = entry.iconPath ? [UIImage imageWithContentsOfFile:entry.iconPath] : nil;
    if (!icon) icon = [UIImage systemImageNamed:entry.isSpringBoard ? @"house" : @"app"];
    iconView.image = icon;
    [header addSubview:iconView];
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(58, 8, tableView.bounds.size.width - 74, 20)];
    nameLabel.text = entry.name;
    nameLabel.font = [UIFont boldSystemFontOfSize:15];
    nameLabel.textColor = [UIColor labelColor];
    [header addSubview:nameLabel];
    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(58, 28, tableView.bounds.size.width - 74, 16)];
    detailLabel.text = [NSString stringWithFormat:@"%@ • %lu tweak", entry.bundleID, (unsigned long)[model[@"tweaks"] count]];
    detailLabel.font = [UIFont systemFontOfSize:12];
    detailLabel.textColor = [UIColor secondaryLabelColor];
    [header addSubview:detailLabel];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"InjectCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    TPInjectedTweak *tweak = self.visibleSections[(NSUInteger)indexPath.section][@"tweaks"][(NSUInteger)indexPath.row];
    cell.textLabel.text = tweak.displayName;
    cell.detailTextLabel.text = [self subtitleForTweak:tweak];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = tweak.disabled ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TPInjectedTweak *tweak = self.visibleSections[(NSUInteger)indexPath.section][@"tweaks"][(NSUInteger)indexPath.row];
    [self showTweakDetail:tweak];
}

- (void)showTweakDetail:(TPInjectedTweak *)tweak {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    [entries addObject:@{ @"path": [NSString stringWithFormat:@"Dylib: %@.dylib", tweak.dylibName] }];
    if (tweak.packageID.length > 0) {
        [entries addObject:@{ @"path": [NSString stringWithFormat:@"Gói: %@%@", tweak.packageID, tweak.packageVersion.length > 0 ? [NSString stringWithFormat:@" (%@)", tweak.packageVersion] : @""] }];
    } else {
        [entries addObject:@{ @"path": @"Gói: không rõ (không thấy trong dpkg)" }];
    }
    NSString *state = tweak.embedded ? @"Nhúng sẵn trong app (bản cài đã chích)" : (tweak.disabled ? @"Đã tắt (dylib bị vô hiệu hoá)" : @"Đang bật");
    [entries addObject:@{ @"path": [NSString stringWithFormat:@"Trạng thái: %@", state] }];
    [entries addObject:@{ @"path": @"— Chích vào: —" }];
    if (tweak.targets.count == 0) {
        [entries addObject:@{ @"path": @"(Không rõ đích đến)" }];
    }
    for (NSString *target in tweak.targets) {
        [entries addObject:@{ @"path": target }];
    }
    TPFileListViewController *vc = [[TPFileListViewController alloc] initWithTitle:tweak.displayName entries:[entries copy]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
