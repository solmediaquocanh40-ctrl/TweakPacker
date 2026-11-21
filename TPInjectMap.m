#import "TPInjectMap.h"
#import "TPDpkg.h"
#import "TPLog.h"
#import <objc/message.h>

@implementation TPInjectedTweak
@end

@implementation TPAppInjectEntry
@end

@interface TPInjectMap ()
+ (NSDictionary<NSString *, NSDictionary *> *)installedApps;
+ (NSString *)iconPathForAppBundleAtPath:(NSString *)bundlePath info:(NSDictionary *)info;
+ (NSDictionary<NSString *, TPPackage *> *)dylibOwners;
+ (TPInjectMap *)buildNow;
@end

@implementation TPInjectMap

#pragma mark - Danh sách app đã cài (LSApplicationWorkspace, dò bằng objc_msgSend)

+ (NSDictionary<NSString *, NSDictionary *> *)installedApps {
    NSMutableDictionary<NSString *, NSDictionary *> *result = [NSMutableDictionary dictionary];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) {
        TPLog(@"InjectMap: khong thay LSApplicationWorkspace");
        return result;
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)(wsClass, @selector(defaultWorkspace));
    if (!workspace) return result;
    NSArray *proxies = ((NSArray *(*)(id, SEL))objc_msgSend)(workspace, @selector(allInstalledApplications));
    NSFileManager *fm = [NSFileManager defaultManager];
    for (id proxy in proxies ?: @[]) {
        @try {
            NSString *bundleID = ((NSString *(*)(id, SEL))objc_msgSend)(proxy, @selector(applicationIdentifier));
            if (bundleID.length == 0) continue;
            NSString *name = nil;
            if ([proxy respondsToSelector:@selector(localizedName)]) {
                name = ((NSString *(*)(id, SEL))objc_msgSend)(proxy, @selector(localizedName));
            }
            NSString *path = nil;
            if ([proxy respondsToSelector:@selector(bundleURL)]) {
                NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(proxy, @selector(bundleURL));
                path = url.path;
            }
            NSDictionary *info = nil;
            NSString *executable = nil;
            NSString *iconPath = nil;
            if (path.length > 0) {
                info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
                executable = info[@"CFBundleExecutable"];
                if (name.length == 0) name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
                    iconPath = [self iconPathForAppBundleAtPath:path info:info];
                }
            }
            result[bundleID] = @{
                @"name": name.length > 0 ? name : bundleID,
                @"path": path ?: @"",
                @"executable": executable ?: @"",
                @"iconPath": iconPath ?: @"",
            };
        } @catch (NSException *exception) {
            TPLog(@"InjectMap: loi doc thong tin app: %@", exception.reason);
        }
    }
    return result;
}

+ (NSString *)iconPathForAppBundleAtPath:(NSString *)bundlePath info:(NSDictionary *)info {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *bases = [NSMutableArray array];
    id icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        id primary = icons[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            id files = primary[@"CFBundleIconFiles"];
            if ([files isKindOfClass:[NSArray class]]) {
                for (id file in (NSArray *)files) {
                    if ([file isKindOfClass:[NSString class]]) [bases addObject:file];
                }
            }
        }
    }
    [bases addObjectsFromArray:@[@"AppIcon60x60", @"AppIcon76x76", @"AppIcon"]];
    for (NSString *base in bases) {
        for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png"]) {
            NSString *candidate = [bundlePath stringByAppendingPathComponent:[base stringByAppendingString:suffix]];
            if ([fm fileExistsAtPath:candidate]) return candidate;
        }
    }
    return nil;
}

#pragma mark - Tra gói sở hữu dylib qua dpkg

+ (NSDictionary<NSString *, TPPackage *> *)dylibOwners {
    NSMutableDictionary<NSString *, TPPackage *> *owners = [NSMutableDictionary dictionary];
    for (TPPackage *package in [TPDpkg installedPackages]) {
        for (NSString *path in package.listedPaths) {
            if (![path.lowercaseString hasSuffix:@".dylib"]) continue;
            NSString *key = path.lastPathComponent.lowercaseString;
            if (!owners[key]) owners[key] = package;
        }
    }
    return owners;
}

#pragma mark - Xây bản đồ

+ (void)buildWithCompletion:(void (^)(TPInjectMap *map))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TPInjectMap *map = [self buildNow];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(map);
        });
    });
}

+ (TPInjectMap *)buildNow {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary<NSString *, NSDictionary *> *apps = [self installedApps];
    NSDictionary<NSString *, TPPackage *> *owners = [self dylibOwners];

    // executable -> bundleID (để gắn filter theo Executables)
    NSMutableDictionary<NSString *, NSString *> *execToBundle = [NSMutableDictionary dictionary];
    for (NSString *bundleID in apps) {
        NSString *exec = apps[bundleID][@"executable"];
        if (exec.length > 0 && !execToBundle[exec]) execToBundle[exec] = bundleID;
    }

    NSMutableDictionary<NSString *, NSMutableArray<TPInjectedTweak *> *> *byApp = [NSMutableDictionary dictionary];
    NSMutableArray<TPInjectedTweak *> *systemWide = [NSMutableArray array];
    NSMutableArray<TPInjectedTweak *> *classBased = [NSMutableArray array];
    NSMutableArray<TPInjectedTweak *> *all = [NSMutableArray array];

    void (^attach)(TPInjectedTweak *, NSString *) = ^(TPInjectedTweak *tweak, NSString *bundleID) {
        NSMutableArray<TPInjectedTweak *> *list = byApp[bundleID];
        if (!list) {
            list = [NSMutableArray array];
            byApp[bundleID] = list;
        }
        if (![list containsObject:tweak]) [list addObject:tweak];
    };

    // ---- Quét filter plist của substrate (ElleKit/Substrate) ----
    NSString *jb = [TPDpkg jbPrefix];
    NSArray<NSString *> *dirs = @[
        [jb stringByAppendingString:@"/Library/MobileSubstrate/DynamicLibraries"],
        [jb stringByAppendingString:@"/usr/lib/TweakInject"],
    ];
    NSMutableDictionary<NSString *, TPInjectedTweak *> *byDylib = [NSMutableDictionary dictionary];
    for (NSString *dir in dirs) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
            if (![file.lowercaseString hasSuffix:@".plist"]) continue;
            NSString *base = file.stringByDeletingPathExtension;
            NSString *key = base.lowercaseString;
            NSString *plistPath = [dir stringByAppendingPathComponent:file];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSDictionary *filter = [plist[@"Filter"] isKindOfClass:[NSDictionary class]] ? plist[@"Filter"] : nil;
            if (!filter) continue;

            NSString *dylibPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".dylib"]];
            BOOL dylibExists = [fm fileExistsAtPath:dylibPath];
            BOOL disabledExists = [fm fileExistsAtPath:[dylibPath stringByAppendingString:@".disabled"]];

            TPInjectedTweak *existing = byDylib[key];
            if (existing) {
                // Hai thư mục thường là một (symlink): gặp lại thì chỉ nâng trạng thái nếu bản này có dylib thật.
                if (existing.disabled && dylibExists) existing.disabled = NO;
                continue;
            }

            TPInjectedTweak *tweak = [[TPInjectedTweak alloc] init];
            tweak.dylibName = base;
            tweak.disabled = !dylibExists && disabledExists;
            tweak.embedded = NO;
            TPPackage *owner = owners[[base.lowercaseString stringByAppendingString:@".dylib"]];
            if (owner) {
                tweak.packageID = owner.packageID;
                tweak.packageVersion = owner.version;
                tweak.displayName = owner.displayName.length > 0 ? owner.displayName : base;
            } else {
                tweak.displayName = base;
            }

            NSMutableArray<NSString *> *targets = [NSMutableArray array];
            NSMutableArray<NSString *> *targetIDs = [NSMutableArray array];
            NSArray *bundles = [filter[@"Bundles"] isKindOfClass:[NSArray class]] ? filter[@"Bundles"] : @[];
            NSArray *executables = [filter[@"Executables"] isKindOfClass:[NSArray class]] ? filter[@"Executables"] : @[];
            NSArray *classes = [filter[@"Classes"] isKindOfClass:[NSArray class]] ? filter[@"Classes"] : @[];

            for (id raw in bundles) {
                if (![raw isKindOfClass:[NSString class]]) continue;
                NSString *bundleID = (NSString *)raw;
                NSString *lower = bundleID.lowercaseString;
                if ([lower isEqualToString:@"com.apple.uikit"] || [lower isEqualToString:@"com.apple.foundation"]) {
                    tweak.systemWide = YES;
                    continue;
                }
                [targetIDs addObject:bundleID];
                if ([lower isEqualToString:@"com.apple.springboard"]) {
                    [targets addObject:@"SpringBoard (màn hình chính)"];
                    attach(tweak, @"com.apple.springboard");
                } else if (apps[bundleID]) {
                    [targets addObject:apps[bundleID][@"name"]];
                    attach(tweak, bundleID);
                } else {
                    [targets addObject:[NSString stringWithFormat:@"%@ (app chưa cài)", bundleID]];
                }
            }
            for (id raw in executables) {
                if (![raw isKindOfClass:[NSString class]]) continue;
                NSString *exec = (NSString *)raw;
                if ([exec isEqualToString:@"SpringBoard"]) {
                    [targets addObject:@"SpringBoard (màn hình chính)"];
                    attach(tweak, @"com.apple.springboard");
                } else if (execToBundle[exec]) {
                    NSString *bundleID = execToBundle[exec];
                    [targetIDs addObject:bundleID];
                    [targets addObject:apps[bundleID][@"name"]];
                    attach(tweak, bundleID);
                } else {
                    [targets addObject:[NSString stringWithFormat:@"Tiến trình: %@", exec]];
                }
            }
            for (id raw in classes) {
                if (![raw isKindOfClass:[NSString class]]) continue;
                [targets addObject:[NSString stringWithFormat:@"Class: %@", (NSString *)raw]];
            }
            if (tweak.systemWide) {
                [targets insertObject:@"Toàn hệ thống (mọi app)" atIndex:0];
                [systemWide addObject:tweak];
            } else if (targets.count == 0 && classes.count > 0) {
                tweak.classBased = YES;
                [classBased addObject:tweak];
            }
            tweak.targets = [targets copy];
            tweak.targetBundleIDs = [targetIDs copy];
            byDylib[key] = tweak;
            [all addObject:tweak];
        }
    }

    // ---- Quét dylib nhúng sẵn trong app người dùng (bản .ipa đã chích) ----
    for (NSString *bundleID in apps) {
        NSString *path = apps[bundleID][@"path"];
        if (path.length == 0) continue;
        if (![path containsString:@"containers/Bundle/Application"]) continue;
        NSMutableArray<NSString *> *loose = [NSMutableArray array];
        for (NSString *entry in [fm contentsOfDirectoryAtPath:path error:nil] ?: @[]) {
            if ([entry.lowercaseString hasSuffix:@".dylib"]) [loose addObject:entry];
        }
        NSString *frameworksDir = [path stringByAppendingPathComponent:@"Frameworks"];
        BOOL substrateInside = NO;
        for (NSString *entry in [fm contentsOfDirectoryAtPath:frameworksDir error:nil] ?: @[]) {
            NSString *lower = entry.lowercaseString;
            if ([lower hasSuffix:@".dylib"]) [loose addObject:entry];
            if ([lower containsString:@"cydiasubstrate"] || [lower containsString:@"libsubstrate"] || [lower containsString:@"ellekit"]) substrateInside = YES;
        }
        for (NSString *dylibFile in loose) {
            TPInjectedTweak *tweak = [[TPInjectedTweak alloc] init];
            tweak.dylibName = dylibFile.stringByDeletingPathExtension;
            tweak.displayName = tweak.dylibName;
            tweak.embedded = YES;
            tweak.targets = @[apps[bundleID][@"name"]];
            tweak.targetBundleIDs = @[bundleID];
            attach(tweak, bundleID);
            [all addObject:tweak];
        }
        if (substrateInside && loose.count == 0) {
            TPInjectedTweak *marker = [[TPInjectedTweak alloc] init];
            marker.dylibName = @"Substrate";
            marker.displayName = @"Có khung chích trong app (không rõ dylib)";
            marker.embedded = YES;
            marker.targets = @[apps[bundleID][@"name"]];
            marker.targetBundleIDs = @[bundleID];
            attach(marker, bundleID);
            [all addObject:marker];
        }
    }

    // ---- Dựng danh sách app ----
    NSMutableArray<TPAppInjectEntry *> *entries = [NSMutableArray array];
    for (NSString *bundleID in byApp) {
        TPAppInjectEntry *entry = [[TPAppInjectEntry alloc] init];
        entry.bundleID = bundleID;
        if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            entry.name = @"SpringBoard (màn hình chính)";
            entry.isSpringBoard = YES;
        } else {
            entry.name = apps[bundleID][@"name"] ?: bundleID;
            NSString *icon = apps[bundleID][@"iconPath"];
            entry.iconPath = icon.length > 0 ? icon : nil;
        }
        NSArray<TPInjectedTweak *> *tweaks = [byApp[bundleID] sortedArrayUsingComparator:^NSComparisonResult(TPInjectedTweak *a, TPInjectedTweak *b) {
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];
        entry.tweaks = tweaks;
        [entries addObject:entry];
    }
    [entries sortUsingComparator:^NSComparisonResult(TPAppInjectEntry *a, TPAppInjectEntry *b) {
        if (a.isSpringBoard != b.isSpringBoard) return a.isSpringBoard ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    TPInjectMap *map = [[TPInjectMap alloc] init];
    map.appEntries = [entries copy];
    map.systemWideTweaks = [systemWide sortedArrayUsingComparator:^NSComparisonResult(TPInjectedTweak *a, TPInjectedTweak *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    map.classTweaks = [classBased sortedArrayUsingComparator:^NSComparisonResult(TPInjectedTweak *a, TPInjectedTweak *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    map.allTweaks = [all sortedArrayUsingComparator:^NSComparisonResult(TPInjectedTweak *a, TPInjectedTweak *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    TPLog(@"InjectMap: %lu app co tweak, %lu tweak tong (%lu toan he thong, %lu theo class)",
          (unsigned long)map.appEntries.count, (unsigned long)map.allTweaks.count,
          (unsigned long)map.systemWideTweaks.count, (unsigned long)map.classTweaks.count);
    return map;
}

@end
