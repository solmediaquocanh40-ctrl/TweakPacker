#import "TPDpkg.h"
#import "TPLog.h"
#include <sys/stat.h>

@implementation TPPackage
@end

@interface TPDpkg ()
+ (NSString *)absolutePath:(NSString *)suffix;
+ (TPPackage *)packageFromStanza:(NSString *)stanza;
+ (NSString *)findIconPathForPackage:(TPPackage *)package;
@end

@implementation TPDpkg

+ (NSString *)jbPrefix {
    static NSString *prefix = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct stat st;
        if (lstat("/var/jb/Library/dpkg/status", &st) == 0) {
            prefix = @"/var/jb";
        } else {
            prefix = @"";
        }
    });
    return prefix;
}

+ (NSString *)absolutePath:(NSString *)suffix {
    return [[self jbPrefix] stringByAppendingString:suffix];
}

+ (NSString *)dpkgInfoDirectory {
    return [self absolutePath:@"/Library/dpkg/info"];
}

+ (BOOL)pathExistsAt:(NSString *)path {
    struct stat st;
    return lstat([path fileSystemRepresentation], &st) == 0;
}

+ (NSString *)realPathForListedPath:(NSString *)listedPath {
    if ([self pathExistsAt:listedPath]) return listedPath;
    NSString *prefix = [self jbPrefix];
    if (prefix.length > 0) {
        NSString *candidate = [prefix stringByAppendingString:listedPath];
        if ([self pathExistsAt:candidate]) return candidate;
    }
    return nil;
}

+ (NSString *)debPathForListedPath:(NSString *)listedPath {
    NSString *p = listedPath;
    if ([p hasPrefix:@"/"]) p = [p substringFromIndex:1];
    if ([p hasPrefix:@"var/jb/"]) p = [p substringFromIndex:7];
    return p;
}

+ (NSArray<TPPackage *> *)installedPackages {
    NSString *statusPath = [self absolutePath:@"/Library/dpkg/status"];
    NSString *raw = [NSString stringWithContentsOfFile:statusPath encoding:NSUTF8StringEncoding error:nil];
    if (raw.length == 0) {
        TPLog(@"Khong doc duoc file trang thai dpkg: %@", statusPath);
        return @[];
    }
    NSMutableArray<TPPackage *> *packages = [NSMutableArray array];
    for (NSString *stanza in [raw componentsSeparatedByString:@"\n\n"]) {
        TPPackage *pkg = [self packageFromStanza:stanza];
        if (pkg) [packages addObject:pkg];
    }
    [packages sortUsingComparator:^NSComparisonResult(TPPackage *a, TPPackage *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    NSUInteger tweakCount = 0;
    for (TPPackage *pkg in packages) {
        if (pkg.isTweak) tweakCount++;
    }
    TPLog(@"Doc dpkg xong: %lu goi (%lu tweak), tien to jb: '%@'", (unsigned long)packages.count, (unsigned long)tweakCount, [self jbPrefix]);
    return [packages copy];
}

+ (TPPackage *)packageFromStanza:(NSString *)stanza {
    NSString *trimmed = [stanza stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;

    NSArray<NSString *> *lines = [trimmed componentsSeparatedByString:@"\n"];
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *controlLines = [NSMutableArray array];
    NSString *currentField = nil;
    BOOL dropCurrent = NO;
    for (NSString *line in lines) {
        BOOL continuation = [line hasPrefix:@" "] || [line hasPrefix:@"\t"];
        if (!continuation) {
            NSRange colon = [line rangeOfString:@": "];
            NSString *key = colon.location == NSNotFound ? line : [line substringToIndex:colon.location];
            NSString *value = colon.location == NSNotFound ? @"" : [line substringFromIndex:colon.location + 2];
            currentField = key;
            dropCurrent = [key isEqualToString:@"Status"] || [key isEqualToString:@"Conffiles"];
            if (fields[key] == nil) fields[key] = value;
        }
        if (!dropCurrent && currentField != nil) {
            [controlLines addObject:line];
        }
    }

    NSString *status = fields[@"Status"] ?: @"";
    if (![status containsString:@"install ok installed"]) return nil;
    NSString *packageID = fields[@"Package"];
    if (packageID.length == 0) return nil;

    TPPackage *pkg = [[TPPackage alloc] init];
    pkg.packageID = packageID;
    NSString *name = fields[@"Name"];
    pkg.displayName = name.length > 0 ? name : packageID;
    pkg.version = fields[@"Version"] ?: @"";
    pkg.architecture = fields[@"Architecture"] ?: @"iphoneos-arm";
    pkg.section = fields[@"Section"] ?: @"";
    NSString *author = fields[@"Author"];
    if (author.length == 0) author = fields[@"Maintainer"];
    pkg.author = author ?: @"";
    pkg.dependsRaw = fields[@"Depends"] ?: @"";
    NSString *desc = fields[@"Description"] ?: @"";
    pkg.shortDescription = [[desc componentsSeparatedByString:@"\n"] firstObject] ?: @"";
    pkg.controlText = [[controlLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];

    NSString *listPath = [[self dpkgInfoDirectory] stringByAppendingPathComponent:[packageID stringByAppendingString:@".list"]];
    NSString *listRaw = [NSString stringWithContentsOfFile:listPath encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if (listRaw) {
        for (NSString *line in [listRaw componentsSeparatedByString:@"\n"]) {
            NSString *p = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (p.length > 0 && ![p isEqualToString:@"/."]) [paths addObject:p];
        }
    }
    pkg.listedPaths = [paths copy];

    BOOL tweak = [pkg.section.lowercaseString hasPrefix:@"tweak"];
    unsigned long long size = 0;
    NSUInteger files = 0;
    for (NSString *listed in pkg.listedPaths) {
        NSString *lower = listed.lowercaseString;
        if ([lower containsString:@"mobilesubstrate/dynamiclibraries/"] ||
            [lower containsString:@"preferencebundles/"] ||
            [lower containsString:@"preferenceloader/preferences/"]) {
            tweak = YES;
        }
        NSString *real = [self realPathForListedPath:listed];
        if (!real) continue;
        struct stat st;
        if (lstat([real fileSystemRepresentation], &st) != 0) continue;
        if (S_ISREG(st.st_mode)) {
            files++;
            size += (unsigned long long)st.st_size;
        } else if (S_ISLNK(st.st_mode)) {
            files++;
        }
    }
    pkg.isTweak = tweak;
    pkg.totalSize = size;
    pkg.fileCount = files;
    return pkg;
}

#pragma mark - Prefs

+ (NSString *)preferencesDirectory {
    return @"/var/mobile/Library/Preferences";
}

+ (NSString *)prefsFilePathForDomain:(NSString *)domain {
    return [[self preferencesDirectory] stringByAppendingPathComponent:[domain stringByAppendingString:@".plist"]];
}

+ (NSArray<NSString *> *)prefsDomainsForPackage:(TPPackage *)package {
    NSMutableArray<NSString *> *domains = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    if (package.packageID.length > 0) {
        [seen addObject:package.packageID];
        [domains addObject:package.packageID];
    }
    for (NSString *listed in package.listedPaths) {
        NSString *lower = listed.lowercaseString;
        if (![lower containsString:@"preferencebundles/"] || ![lower hasSuffix:@"root.plist"]) continue;
        NSString *real = [self realPathForListedPath:listed];
        if (!real) continue;
        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:real];
        NSArray *items = root[@"items"];
        if (![items isKindOfClass:[NSArray class]]) continue;
        for (id item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *def = item[@"defaults"];
            if ([def isKindOfClass:[NSString class]] && def.length > 0 && ![seen containsObject:def]) {
                [seen addObject:def];
                [domains addObject:def];
            }
        }
    }
    return [domains copy];
}

#pragma mark - Dò file prefs (3 lớp)

+ (NSArray<NSString *> *)preferencesDirectories {
    NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObject:@"/var/mobile/Library/Preferences"];
    NSString *jb = [[self jbPrefix] stringByAppendingString:@"/Library/Preferences"];
    if (![dirs containsObject:jb]) [dirs addObject:jb];
    return [dirs copy];
}

static NSUInteger TPLongestCommonPrefixLength(NSString *a, NSString *b) {
    NSUInteger n = MIN(a.length, b.length);
    NSUInteger i = 0;
    while (i < n && [a characterAtIndex:i] == [b characterAtIndex:i]) i++;
    return i;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)prefsFilesForPackage:(TPPackage *)package {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^addFile)(NSString *, NSString *) = ^(NSString *label, NSString *path) {
        if (path.length == 0 || [seen containsObject:path]) return;
        if (![TPDpkg pathExistsAt:path]) return;
        [seen addObject:path];
        [results addObject:@{ @"label": label ?: @"", @"source": path }];
        TPLog(@"Prefs: tim thay [%@] -> %@", label, path);
    };

    // Lớp 1: domain ứng viên (package ID + defaults trong Root.plist + bundle id của PreferenceBundle).
    NSMutableArray<NSString *> *domains = [[self prefsDomainsForPackage:package] mutableCopy];
    for (NSString *listed in package.listedPaths) {
        NSString *lower = listed.lowercaseString;
        if (![lower containsString:@"preferencebundles/"] || ![lower hasSuffix:@"info.plist"]) continue;
        NSString *real = [self realPathForListedPath:listed];
        if (!real) continue;
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:real];
        NSString *bundleID = info[@"CFBundleIdentifier"];
        if ([bundleID isKindOfClass:[NSString class]] && bundleID.length > 0 && ![domains containsObject:bundleID]) {
            [domains addObject:bundleID];
        }
    }
    NSArray<NSString *> *dirs = [self preferencesDirectories];
    for (NSString *domain in domains) {
        for (NSString *dir in dirs) {
            addFile(domain, [dir stringByAppendingPathComponent:[domain stringByAppendingString:@".plist"]]);
        }
    }

    // Lớp 2: quét tên gần giống (domain không trùng package ID vẫn bắt được).
    NSString *pidLower = package.packageID.lowercaseString;
    NSString *lastComp = pidLower.lastPathComponent;
    for (NSString *dir in dirs) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
            if (![file.lowercaseString hasSuffix:@".plist"]) continue;
            NSString *base = file.stringByDeletingPathExtension.lowercaseString;
            BOOL nameHit = (lastComp.length >= 4 && [base containsString:lastComp]);
            BOOL prefixHit = TPLongestCommonPrefixLength(base, pidLower) >= 12;
            if ([base isEqualToString:pidLower] || nameHit || prefixHit) {
                addFile(base, [dir stringByAppendingPathComponent:file]);
            }
        }
    }

    // Lớp 3: thư mục riêng của tweak trong Library (vd /var/jb/Library/LiquidGlaze/).
    if (lastComp.length >= 4) {
        NSArray<NSString *> *libraryRoots = @[[[self jbPrefix] stringByAppendingString:@"/Library"], @"/var/mobile/Library"];
        for (NSString *root in libraryRoots) {
            for (NSString *folder in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
                if (![folder.lowercaseString containsString:lastComp]) continue;
                NSString *folderPath = [root stringByAppendingPathComponent:folder];
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:folderPath isDirectory:&isDir] || !isDir) continue;
                NSUInteger added = 0;
                for (NSString *file in [fm contentsOfDirectoryAtPath:folderPath error:nil] ?: @[]) {
                    if (![file.lowercaseString hasSuffix:@".plist"]) continue;
                    if (added >= 5) break;
                    addFile([NSString stringWithFormat:@"%@/%@", folder, file], [folderPath stringByAppendingPathComponent:file]);
                    added++;
                }
            }
        }
    }

    TPLog(@"Prefs: %@ — tong cong %lu file", package.packageID, (unsigned long)results.count);
    return [results copy];
}

#pragma mark - Icon

+ (NSString *)iconPathForPackage:(TPPackage *)package {
    static NSMutableDictionary<NSString *, id> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    id cached = cache[package.packageID];
    if (cached != nil) {
        return [cached isKindOfClass:[NSString class]] ? cached : nil;
    }
    NSString *found = [self findIconPathForPackage:package];
    cache[package.packageID] = found ?: [NSNull null];
    return found;
}

+ (NSString *)findIconPathForPackage:(TPPackage *)package {
    // 1) Icon khai trong mục PreferenceLoader.
    for (NSString *listed in package.listedPaths) {
        NSString *lower = listed.lowercaseString;
        if (![lower containsString:@"preferenceloader/preferences/"] || ![lower hasSuffix:@".plist"]) continue;
        NSString *real = [self realPathForListedPath:listed];
        if (!real) continue;
        NSDictionary *entryPlist = [NSDictionary dictionaryWithContentsOfFile:real];
        NSDictionary *entry = entryPlist[@"entry"];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *icon = entry[@"icon"];
        if (![icon isKindOfClass:[NSString class]] || icon.length == 0) continue;
        if ([icon hasPrefix:@"/"]) {
            NSString *p = [self realPathForListedPath:icon];
            if (p) return p;
        }
        NSString *base = [icon stringByDeletingPathExtension];
        for (NSString *candidate in @[icon,
                                      [icon stringByAppendingString:@".png"],
                                      [base stringByAppendingString:@"@2x.png"],
                                      [base stringByAppendingString:@"@3x.png"]]) {
            NSString *p = [self realPathForListedPath:[@"/Library/PreferenceLoader/Icons/" stringByAppendingString:candidate]];
            if (p) return p;
        }
    }
    // 2) icon.png trong .bundle, rồi AppIcon trong .app.
    NSString *appIconPath = nil;
    for (NSString *listed in package.listedPaths) {
        NSString *lower = listed.lowercaseString;
        NSString *last = lower.lastPathComponent;
        if ([lower containsString:@".bundle/"] &&
            ([last isEqualToString:@"icon.png"] || [last isEqualToString:@"icon@2x.png"] || [last isEqualToString:@"icon@3x.png"])) {
            NSString *p = [self realPathForListedPath:listed];
            if (p) return p;
        }
        if (appIconPath == nil && [lower containsString:@".app/"] && [last hasPrefix:@"appicon60x60"]) {
            appIconPath = [self realPathForListedPath:listed];
        }
    }
    return appIconPath;
}

@end
