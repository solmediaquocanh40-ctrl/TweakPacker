#import "TPDpkg.h"
#import "TPLog.h"
#include <sys/stat.h>

@implementation TPPackage
@end

@interface TPDpkg ()
+ (NSString *)absolutePath:(NSString *)suffix;
+ (TPPackage *)packageFromStanza:(NSString *)stanza;
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

@end
