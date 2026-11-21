#import "TPTheme.h"
#import "TPDebBuilder.h"
#import "TPLog.h"

static NSString * const TPThemeModeKey = @"TPThemeMode";
static const NSInteger TPContainerTag = 7700;
static const NSInteger TPEmptyLabelTag = 7701;

@implementation TPTheme

+ (NSInteger)currentMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:TPThemeModeKey];
}

+ (void)setMode:(NSInteger)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:TPThemeModeKey];
    TPLog(@"Doi nen ung dung: che do %ld", (long)mode);
}

+ (NSArray<NSString *> *)modeNames {
    return @[@"Theo hệ thống", @"Đen tuyền", @"Ngọc lục bảo", @"Xanh dương", @"Tím", @"Cam", @"Hồng", @"Ảnh tuỳ chọn"];
}

#pragma mark - Ảnh nền

+ (NSString *)backgroundImagePath {
    return [[TPDebBuilder outputDirectory] stringByAppendingPathComponent:@"theme-background.jpg"];
}

+ (void)saveBackgroundImage:(UIImage *)image {
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    [data writeToFile:[self backgroundImagePath] atomically:YES];
}

+ (UIImage *)backgroundImage {
    return [UIImage imageWithContentsOfFile:[self backgroundImagePath]];
}

+ (void)removeBackgroundImage {
    [[NSFileManager defaultManager] removeItemAtPath:[self backgroundImagePath] error:nil];
    if ([self currentMode] == 7) [self setMode:0];
}

#pragma mark - Màu nền

+ (UIColor *)dynamicColorWithLight:(UIColor *)light dark:(UIColor *)dark {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

+ (UIColor *)backgroundColorForMode:(NSInteger)mode tableStyle:(UITableViewStyle)style {
    switch (mode) {
        case 1:
            return [UIColor blackColor];
        case 2:
            return [self dynamicColorWithLight:[UIColor colorWithRed:0.87 green:0.97 blue:0.92 alpha:1.0]
                                          dark:[UIColor colorWithRed:0.03 green:0.13 blue:0.09 alpha:1.0]];
        case 3:
            return [self dynamicColorWithLight:[UIColor colorWithRed:0.88 green:0.93 blue:1.0 alpha:1.0]
                                          dark:[UIColor colorWithRed:0.04 green:0.09 blue:0.18 alpha:1.0]];
        case 4:
            return [self dynamicColorWithLight:[UIColor colorWithRed:0.94 green:0.90 blue:1.0 alpha:1.0]
                                          dark:[UIColor colorWithRed:0.11 green:0.06 blue:0.20 alpha:1.0]];
        case 5:
            return [self dynamicColorWithLight:[UIColor colorWithRed:1.0 green:0.93 blue:0.84 alpha:1.0]
                                          dark:[UIColor colorWithRed:0.20 green:0.11 blue:0.03 alpha:1.0]];
        case 6:
            return [self dynamicColorWithLight:[UIColor colorWithRed:1.0 green:0.89 blue:0.94 alpha:1.0]
                                          dark:[UIColor colorWithRed:0.20 green:0.06 blue:0.12 alpha:1.0]];
        default:
            return style == UITableViewStylePlain ? [UIColor systemBackgroundColor] : [UIColor systemGroupedBackgroundColor];
    }
}

+ (UIColor *)accentColorForMode:(NSInteger)mode {
    switch (mode) {
        case 2: return [UIColor colorWithRed:0.05 green:0.65 blue:0.45 alpha:1.0];
        case 3: return [UIColor systemBlueColor];
        case 4: return [UIColor systemPurpleColor];
        case 5: return [UIColor systemOrangeColor];
        case 6: return [UIColor systemPinkColor];
        default: return nil;
    }
}

+ (void)applyTintToWindow:(UIWindow *)window {
    window.tintColor = [self accentColorForMode:[self currentMode]];
}

+ (void)applyTintToAllWindows {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in [(UIWindowScene *)scene windows]) {
            [self applyTintToWindow:window];
        }
    }
}

#pragma mark - Áp nền

+ (UIView *)imageContainerWithImage:(UIImage *)image {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    container.tag = TPContainerTag;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.frame = container.bounds;
    [container addSubview:imageView];
    UIView *dim = [[UIView alloc] initWithFrame:container.bounds];
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:dim];
    return container;
}

+ (BOOL)imageModeActive {
    return [self currentMode] == 7 && [self backgroundImage] != nil;
}

+ (void)applyToTableView:(UITableView *)tableView {
    if ([self imageModeActive]) {
        tableView.backgroundColor = [UIColor clearColor];
        tableView.backgroundView = [self imageContainerWithImage:[self backgroundImage]];
        return;
    }
    tableView.backgroundView = nil;
    NSInteger mode = [self currentMode];
    if (mode == 7) mode = 0;
    tableView.backgroundColor = [self backgroundColorForMode:mode tableStyle:tableView.style];
}

+ (void)setEmptyMessage:(NSString *)message forTableView:(UITableView *)tableView {
    if ([self imageModeActive]) {
        if (tableView.backgroundView == nil || tableView.backgroundView.tag != TPContainerTag) {
            [self applyToTableView:tableView];
        }
        UIView *container = tableView.backgroundView;
        UILabel *label = (UILabel *)[container viewWithTag:TPEmptyLabelTag];
        if (message.length == 0) {
            label.hidden = YES;
            return;
        }
        if (!label) {
            label = [[UILabel alloc] init];
            label.tag = TPEmptyLabelTag;
            label.numberOfLines = 0;
            label.textAlignment = NSTextAlignmentCenter;
            label.font = [UIFont systemFontOfSize:15];
            label.textColor = [UIColor whiteColor];
            label.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
            label.shadowOffset = CGSizeMake(0, 1);
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [container addSubview:label];
            [NSLayoutConstraint activateConstraints:@[
                [label.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
                [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
                [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:24],
                [label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-24],
            ]];
        }
        label.text = message;
        label.hidden = NO;
        return;
    }
    if (message.length == 0) {
        tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor secondaryLabelColor];
    tableView.backgroundView = label;
}

@end

#pragma mark - Mở thư mục

@implementation TPOpenFolder

+ (void)presentFromViewController:(UIViewController *)viewController path:(NSString *)path anchorView:(UIView *)anchorView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Mở thư mục" message:path preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mở trong Filza" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
        NSURL *url = [NSURL URLWithString:[@"filza://view" stringByAppendingString:encoded ?: path]];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                [UIPasteboard generalPasteboard].string = path;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chưa mở được Filza" message:@"Có thể máy chưa cài Filza. Em đã sao chép đường dẫn, anh dán vào Filza/Files là tới nơi." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [viewController presentViewController:alert animated:YES completion:nil];
            }
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mở trong Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
        NSURL *url = [NSURL URLWithString:[@"shareddocuments://" stringByAppendingString:encoded ?: path]];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Sao chép đường dẫn" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = path;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = anchorView ?: viewController.view;
    sheet.popoverPresentationController.sourceRect = anchorView ? anchorView.bounds : CGRectMake(viewController.view.bounds.size.width / 2.0, viewController.view.bounds.size.height / 2.0, 1, 1);
    [viewController presentViewController:sheet animated:YES completion:nil];
}

@end
