#import "TPBackupManager.h"
#import "TPDpkg.h"
#import "TPDebBuilder.h"
#import "TPDebReader.h"
#import "TPLog.h"
#include <sys/stat.h>

@implementation TPBackupItem

- (BOOL)hasPrefs {
    return self.prefsBackups.count > 0;
}

- (NSUInteger)fileCount {
    NSUInteger n = 0;
    for (NSDictionary *f in self.fileList) {
        NSString *type = f[@"type"];
        if ([type isEqualToString:@"0"] || [type isEqualToString:@"2"]) n++;
    }
    return n;
}

- (NSString *)sessionDirectory {
    if (self.sessionName.length > 0) {
        return [[TPBackupManager backupRoot] stringByAppendingPathComponent:self.sessionName];
    }
    return [TPBackupManager backupRoot];
}

@end

@interface TPBackupManager ()
+ (TPBackupItem *)itemFromManifestAtPath:(NSString *)manifestPath sessionName:(NSString *)sessionName;
+ (TPBackupItem *)legacyItemForDebAtPath:(NSString *)debPath;
+ (NSString *)historyFilePath;
+ (NSDateFormatter *)sessionNameFormatter;
@end

@implementation TPBackupManager

+ (NSString *)backupRoot {
    return [TPDebBuilder outputDirectory];
}

+ (NSDateFormatter *)sessionNameFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return formatter;
}

+ (NSString *)createSessionDirectory {
    NSString *root = [self backupRoot];
    NSString *base = [@"Backup-" stringByAppendingString:[[self sessionNameFormatter] stringFromDate:[NSDate date]]];
    NSString *name = base;
    NSUInteger suffix = 1;
    while ([TPDpkg pathExistsAt:[root stringByAppendingPathComponent:name]]) {
        suffix++;
        name = [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)suffix];
    }
    NSString *path = [root stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    TPLog(@"Tao thu muc dot backup: %@", name);
    return path;
}

#pragma mark - Backup

+ (TPBackupItem *)backupPackage:(TPPackage *)package intoSession:(NSString *)sessionDirectory progress:(void (^)(NSString *, float))progress error:(NSString **)errorMessage {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (progress) progress(@"Đang đóng gói .deb…", 0.15f);

    NSUInteger packed = 0;
    NSUInteger skipped = 0;
    NSError *buildError = nil;
    NSString *debPath = [TPDebBuilder buildDebForPackage:package toDirectory:sessionDirectory fileCount:&packed skipped:&skipped error:&buildError];
    if (!debPath) {
        NSString *message = buildError.localizedDescription ?: @"Đóng gói .deb thất bại";
        if (errorMessage) *errorMessage = message;
        [self recordHistoryAction:@"Backup" packageID:package.packageID ok:NO detail:message];
        return nil;
    }

    if (progress) progress(@"Đang backup thông số (prefs)…", 0.55f);
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *prefsBackups = [NSMutableArray array];
    for (NSString *domain in [TPDpkg prefsDomainsForPackage:package]) {
        NSString *src = [TPDpkg prefsFilePathForDomain:domain];
        if (![TPDpkg pathExistsAt:src]) continue;
        NSString *fileName = [NSString stringWithFormat:@"%@.prefs.%@.plist", package.packageID, domain];
        NSString *dest = [sessionDirectory stringByAppendingPathComponent:fileName];
        NSUInteger n = 1;
        while ([TPDpkg pathExistsAt:dest]) {
            n++;
            fileName = [NSString stringWithFormat:@"%@.prefs.%@-%lu.plist", package.packageID, domain, (unsigned long)n];
            dest = [sessionDirectory stringByAppendingPathComponent:fileName];
        }
        NSError *copyError = nil;
        if ([fm copyItemAtPath:src toPath:dest error:&copyError]) {
            [prefsBackups addObject:@{ @"domain": domain, @"file": fileName }];
            TPLog(@"Da backup prefs %@ -> %@", domain, fileName);
        } else {
            TPLog(@"Khong chep duoc prefs %@: %@", domain, copyError.localizedDescription);
        }
    }

    if (progress) progress(@"Đang kiểm tra lại file .deb…", 0.8f);
    // Kiểm tra toàn vẹn: đọc lại .deb vừa tạo, đối chiếu tập file với danh sách gốc.
    NSMutableSet<NSString *> *expected = [NSMutableSet set];
    for (NSString *listed in package.listedPaths) {
        NSString *real = [TPDpkg realPathForListedPath:listed];
        if (!real) continue;
        struct stat st;
        if (lstat([real fileSystemRepresentation], &st) != 0) continue;
        if (S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) {
            [expected addObject:[TPDpkg debPathForListedPath:listed]];
        }
    }
    NSError *readError = nil;
    TPDebReader *reader = [TPDebReader readerWithPath:debPath error:&readError];
    NSMutableSet<NSString *> *found = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *fileList = [NSMutableArray array];
    NSArray<NSString *> *scriptNames = @[];
    if (reader) {
        for (TPDebEntry *entry in reader.dataEntries) {
            [fileList addObject:@{ @"path": entry.path,
                                   @"size": @(entry.size),
                                   @"type": [NSString stringWithFormat:@"%c", entry.type] }];
            if (entry.isFile || entry.isLink) [found addObject:entry.path];
        }
        scriptNames = reader.maintainerScriptNames;
    }
    NSMutableSet<NSString *> *missing = [expected mutableCopy];
    [missing minusSet:found];
    BOOL integrityOK = reader != nil && missing.count == 0 && found.count == expected.count;
    NSString *integrityNote = nil;
    if (reader == nil) {
        integrityNote = [NSString stringWithFormat:@"Không đọc lại được .deb: %@", readError.localizedDescription ?: @"lỗi không rõ"];
    } else if (integrityOK) {
        integrityNote = [NSString stringWithFormat:@"Đủ %lu/%lu file", (unsigned long)found.count, (unsigned long)expected.count];
    } else {
        integrityNote = [NSString stringWithFormat:@"Có %lu file, thiếu %lu so với danh sách gốc (%lu)", (unsigned long)found.count, (unsigned long)missing.count, (unsigned long)expected.count];
    }

    NSDate *now = [NSDate date];
    NSDictionary *manifest = @{
        @"package": package.packageID ?: @"",
        @"name": package.displayName ?: @"",
        @"version": package.version ?: @"",
        @"author": package.author ?: @"",
        @"date": @([now timeIntervalSince1970]),
        @"deb": debPath.lastPathComponent ?: @"",
        @"prefs": [prefsBackups copy],
        @"files": [fileList copy],
        @"depends": package.dependsRaw ?: @"",
        @"scripts": scriptNames ?: @[],
        @"integrityOK": @(integrityOK),
        @"integrityNote": integrityNote ?: @"",
    };
    NSString *manifestPath = [sessionDirectory stringByAppendingPathComponent:[package.packageID stringByAppendingString:@".manifest.json"]];
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [manifestData writeToFile:manifestPath atomically:YES];

    TPBackupItem *item = [[TPBackupItem alloc] init];
    item.sessionName = sessionDirectory.lastPathComponent;
    item.date = now;
    item.packageID = package.packageID;
    item.displayName = package.displayName;
    item.version = package.version;
    item.author = package.author;
    item.debPath = debPath;
    struct stat dst;
    item.debSize = lstat([debPath fileSystemRepresentation], &dst) == 0 ? (unsigned long long)dst.st_size : 0;
    item.prefsBackups = [prefsBackups copy];
    item.fileList = [fileList copy];
    item.dependsRaw = package.dependsRaw;
    item.scriptNames = scriptNames;
    item.integrityOK = integrityOK;
    item.integrityNote = integrityNote;
    item.legacy = NO;

    if (progress) progress(@"Xong", 1.0f);
    [self recordHistoryAction:@"Backup" packageID:package.packageID ok:YES
                       detail:[NSString stringWithFormat:@"%@ — %@ (%@)", package.version, integrityNote, prefsBackups.count > 0 ? @"có prefs" : @"không có prefs"]];
    TPLog(@"Backup xong %@: %@, prefs: %lu file", package.packageID, integrityNote, (unsigned long)prefsBackups.count);
    return item;
}

#pragma mark - Quét kho

+ (NSArray<TPBackupItem *> *)allItems {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = [self backupRoot];
    NSMutableArray<TPBackupItem *> *items = [NSMutableArray array];
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *child in children) {
        NSString *childPath = [root stringByAppendingPathComponent:child];
        BOOL isDir = NO;
        [fm fileExistsAtPath:childPath isDirectory:&isDir];
        if (isDir && [child hasPrefix:@"Backup-"]) {
            for (NSString *inner in [fm contentsOfDirectoryAtPath:childPath error:nil] ?: @[]) {
                if ([inner hasSuffix:@".manifest.json"]) {
                    TPBackupItem *item = [self itemFromManifestAtPath:[childPath stringByAppendingPathComponent:inner] sessionName:child];
                    if (item) [items addObject:item];
                }
            }
        } else if (!isDir && [child.lowercaseString hasSuffix:@".deb"]) {
            TPBackupItem *item = [self legacyItemForDebAtPath:childPath];
            if (item) [items addObject:item];
        }
    }
    [items sortUsingComparator:^NSComparisonResult(TPBackupItem *a, TPBackupItem *b) {
        return [b.date compare:a.date];
    }];
    return [items copy];
}

+ (TPBackupItem *)itemFromManifestAtPath:(NSString *)manifestPath sessionName:(NSString *)sessionName {
    NSData *data = [NSData dataWithContentsOfFile:manifestPath];
    if (!data) return nil;
    NSDictionary *m = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![m isKindOfClass:[NSDictionary class]]) return nil;
    NSString *sessionDir = manifestPath.stringByDeletingLastPathComponent;
    TPBackupItem *item = [[TPBackupItem alloc] init];
    item.sessionName = sessionName;
    item.date = [NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]];
    item.packageID = m[@"package"] ?: @"";
    item.displayName = m[@"name"] ?: item.packageID;
    item.version = m[@"version"] ?: @"";
    item.author = m[@"author"] ?: @"";
    item.debPath = [sessionDir stringByAppendingPathComponent:m[@"deb"] ?: @""];
    struct stat st;
    item.debSize = lstat([item.debPath fileSystemRepresentation], &st) == 0 ? (unsigned long long)st.st_size : 0;
    item.prefsBackups = [m[@"prefs"] isKindOfClass:[NSArray class]] ? m[@"prefs"] : @[];
    item.fileList = [m[@"files"] isKindOfClass:[NSArray class]] ? m[@"files"] : @[];
    item.dependsRaw = m[@"depends"] ?: @"";
    item.scriptNames = [m[@"scripts"] isKindOfClass:[NSArray class]] ? m[@"scripts"] : @[];
    item.integrityOK = [m[@"integrityOK"] boolValue];
    item.integrityNote = m[@"integrityNote"] ?: @"";
    item.legacy = NO;
    if (![TPDpkg pathExistsAt:item.debPath]) return nil;
    return item;
}

+ (TPBackupItem *)legacyItemForDebAtPath:(NSString *)debPath {
    NSError *error = nil;
    TPDebReader *reader = [TPDebReader readerWithPath:debPath error:&error];
    if (!reader) {
        TPLog(@"Bo qua .deb le khong doc duoc %@: %@", debPath.lastPathComponent, error.localizedDescription);
        return nil;
    }
    TPBackupItem *item = [[TPBackupItem alloc] init];
    item.sessionName = @"";
    item.packageID = [reader controlField:@"Package"];
    if (item.packageID.length == 0) item.packageID = debPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *name = [reader controlField:@"Name"];
    item.displayName = name.length > 0 ? name : item.packageID;
    item.version = [reader controlField:@"Version"];
    NSString *author = [reader controlField:@"Author"];
    if (author.length == 0) author = [reader controlField:@"Maintainer"];
    item.author = author;
    item.debPath = debPath;
    struct stat st;
    if (lstat([debPath fileSystemRepresentation], &st) == 0) {
        item.debSize = (unsigned long long)st.st_size;
        item.date = [NSDate dateWithTimeIntervalSince1970:st.st_mtime];
    }
    NSMutableArray<NSDictionary *> *fileList = [NSMutableArray array];
    for (TPDebEntry *entry in reader.dataEntries) {
        [fileList addObject:@{ @"path": entry.path,
                               @"size": @(entry.size),
                               @"type": [NSString stringWithFormat:@"%c", entry.type] }];
    }
    item.fileList = [fileList copy];
    item.prefsBackups = @[];
    item.dependsRaw = [reader controlField:@"Depends"];
    item.scriptNames = reader.maintainerScriptNames;
    item.integrityOK = YES;
    item.integrityNote = @"Bản lẻ từ TweakPacker 1.0.0 — chưa có manifest/prefs";
    item.legacy = YES;
    return item;
}

+ (BOOL)deleteItem:(TPBackupItem *)item error:(NSString **)errorMessage {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *sessionDir = [item sessionDirectory];
    NSMutableArray<NSString *> *targets = [NSMutableArray arrayWithObject:item.debPath];
    for (NSDictionary<NSString *, NSString *> *prefs in item.prefsBackups) {
        NSString *file = prefs[@"file"];
        if (file.length > 0) [targets addObject:[sessionDir stringByAppendingPathComponent:file]];
    }
    if (!item.legacy) {
        [targets addObject:[sessionDir stringByAppendingPathComponent:[item.packageID stringByAppendingString:@".manifest.json"]]];
    }
    for (NSString *path in targets) {
        NSError *error = nil;
        if ([TPDpkg pathExistsAt:path] && ![fm removeItemAtPath:path error:&error]) {
            if (errorMessage) *errorMessage = error.localizedDescription;
            return NO;
        }
    }
    if (!item.legacy) {
        NSArray *rest = [fm contentsOfDirectoryAtPath:sessionDir error:nil];
        if (rest.count == 0) [fm removeItemAtPath:sessionDir error:nil];
    }
    [self recordHistoryAction:@"Xoá backup" packageID:item.packageID ok:YES detail:item.version];
    TPLog(@"Da xoa ban backup %@ %@", item.packageID, item.version);
    return YES;
}

+ (unsigned long long)totalSizeOfItems:(NSArray<TPBackupItem *> *)items {
    unsigned long long total = 0;
    for (TPBackupItem *item in items) total += item.debSize;
    return total;
}

#pragma mark - Nhật ký

+ (NSString *)historyFilePath {
    return [[self backupRoot] stringByAppendingPathComponent:@"history.json"];
}

+ (void)recordHistoryAction:(NSString *)action packageID:(NSString *)packageID ok:(BOOL)ok detail:(NSString *)detail {
    NSString *path = [self historyFilePath];
    NSMutableArray *entries = [NSMutableArray array];
    NSData *existing = [NSData dataWithContentsOfFile:path];
    if (existing) {
        id parsed = [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil];
        if ([parsed isKindOfClass:[NSArray class]]) [entries addObjectsFromArray:parsed];
    }
    [entries addObject:@{
        @"time": @([[NSDate date] timeIntervalSince1970]),
        @"action": action ?: @"",
        @"package": packageID ?: @"",
        @"ok": @(ok),
        @"detail": detail ?: @"",
    }];
    while (entries.count > 300) [entries removeObjectAtIndex:0];
    NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
    [data writeToFile:path atomically:YES];
}

+ (NSArray<NSDictionary *> *)historyEntries {
    NSData *data = [NSData dataWithContentsOfFile:[self historyFilePath]];
    if (!data) return @[];
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![parsed isKindOfClass:[NSArray class]]) return @[];
    return [[(NSArray *)parsed reverseObjectEnumerator] allObjects];
}

#pragma mark - So sánh

+ (NSDictionary *)compareItem:(TPBackupItem *)a withItem:(TPBackupItem *)b {
    NSMutableDictionary<NSString *, NSNumber *> *mapA = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *mapB = [NSMutableDictionary dictionary];
    for (NSDictionary *f in a.fileList) {
        NSString *type = f[@"type"];
        if ([type isEqualToString:@"0"] || [type isEqualToString:@"2"]) mapA[f[@"path"]] = f[@"size"];
    }
    for (NSDictionary *f in b.fileList) {
        NSString *type = f[@"type"];
        if ([type isEqualToString:@"0"] || [type isEqualToString:@"2"]) mapB[f[@"path"]] = f[@"size"];
    }
    NSMutableArray<NSString *> *added = [NSMutableArray array];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *changed = [NSMutableArray array];
    for (NSString *path in mapB) {
        if (!mapA[path]) [added addObject:path];
    }
    for (NSString *path in mapA) {
        if (!mapB[path]) {
            [removed addObject:path];
        } else if (![mapA[path] isEqualToNumber:mapB[path]]) {
            [changed addObject:@{ @"path": path, @"sizeA": mapA[path], @"sizeB": mapB[path] }];
        }
    }
    [added sortUsingSelector:@selector(compare:)];
    [removed sortUsingSelector:@selector(compare:)];
    [changed sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        return [x[@"path"] compare:y[@"path"]];
    }];
    return @{ @"added": [added copy], @"removed": [removed copy], @"changed": [changed copy] };
}

@end
