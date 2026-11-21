#import "TPRestoreManager.h"
#import "TPBackupManager.h"
#import "TPDpkg.h"
#import "TPDebReader.h"
#import "TPLog.h"
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <signal.h>
#include <spawn.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

extern char **environ;

#pragma mark - So sánh phiên bản (đủ dùng cho cảnh báo hạ cấp)

static NSArray<NSString *> *TPVersionRuns(NSString *version) {
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < version.length) {
        unichar c = [version characterAtIndex:i];
        BOOL digit = (c >= '0' && c <= '9');
        NSUInteger j = i;
        while (j < version.length) {
            unichar d = [version characterAtIndex:j];
            if (((d >= '0' && d <= '9')) != digit) break;
            j++;
        }
        [runs addObject:[version substringWithRange:NSMakeRange(i, j - i)]];
        i = j;
    }
    return [runs copy];
}

static BOOL TPIsDigitRun(NSString *run) {
    if (run.length == 0) return NO;
    unichar c = [run characterAtIndex:0];
    return c >= '0' && c <= '9';
}

// <0 nếu a<b, 0 nếu bằng, >0 nếu a>b.
static int TPCompareVersions(NSString *a, NSString *b) {
    NSArray<NSString *> *ra = TPVersionRuns(a ?: @"");
    NSArray<NSString *> *rb = TPVersionRuns(b ?: @"");
    NSUInteger n = MAX(ra.count, rb.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *x = i < ra.count ? ra[i] : @"";
        NSString *y = i < rb.count ? rb[i] : @"";
        if ([x isEqualToString:y]) continue;
        if (TPIsDigitRun(x) && TPIsDigitRun(y)) {
            NSString *xs = [x stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]];
            NSString *ys = [y stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]];
            if (xs.length != ys.length) return xs.length > ys.length ? 1 : -1;
            int cmp = [xs compare:ys];
            if (cmp != 0) return cmp > 0 ? 1 : -1;
            continue;
        }
        if ([x isEqualToString:@"~"]) return -1;
        if ([y isEqualToString:@"~"]) return 1;
        int cmp = [x compare:y];
        if (cmp != 0) return cmp > 0 ? 1 : -1;
    }
    return 0;
}

#pragma mark - Đường dẫn đích khi restore

static NSString *TPDestinationForDebPath(NSString *debPath) {
    if ([debPath isEqualToString:@"var/mobile"] || [debPath hasPrefix:@"var/mobile/"]) {
        return [@"/" stringByAppendingString:debPath];
    }
    return [[TPDpkg jbPrefix] stringByAppendingFormat:@"/%@", debPath];
}

@interface TPRestoreManager ()
+ (NSSet<NSString *> *)installedAndProvidedIDs;
+ (NSString *)installedVersionForPackageID:(NSString *)packageID;
+ (NSString *)dpkgStatusPath;
+ (BOOL)updateDpkgForItem:(TPBackupItem *)item reader:(TPDebReader *)reader error:(NSString **)errorMessage;
@end

@implementation TPRestoreManager

+ (NSString *)dpkgStatusPath {
    return [[TPDpkg jbPrefix] stringByAppendingString:@"/Library/dpkg/status"];
}

+ (NSSet<NSString *> *)installedAndProvidedIDs {
    NSString *raw = [NSString stringWithContentsOfFile:[self dpkgStatusPath] encoding:NSUTF8StringEncoding error:nil];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (NSString *stanza in [raw componentsSeparatedByString:@"\n\n"]) {
        if (![stanza containsString:@"install ok installed"]) continue;
        for (NSString *line in [stanza componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"Package: "]) {
                [ids addObject:[line substringFromIndex:9]];
            } else if ([line hasPrefix:@"Provides: "]) {
                NSString *provides = [line substringFromIndex:10];
                for (NSString *part in [provides componentsSeparatedByString:@","]) {
                    NSString *p = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSRange paren = [p rangeOfString:@"("];
                    if (paren.location != NSNotFound) p = [[p substringToIndex:paren.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (p.length > 0) [ids addObject:p];
                }
            }
        }
    }
    return [ids copy];
}

+ (NSString *)installedVersionForPackageID:(NSString *)packageID {
    for (TPPackage *pkg in [TPDpkg installedPackages]) {
        if ([pkg.packageID isEqualToString:packageID]) return pkg.version;
    }
    return nil;
}

+ (NSArray<NSString *> *)missingDependenciesForItem:(TPBackupItem *)item {
    static NSSet<NSString *> *virtualIDs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        virtualIDs = [NSSet setWithObjects:@"firmware", @"base", @"apt", @"apt7", @"dpkg", @"tar",
                        @"coreutils", @"coreutils-bin", @"bash", @"sh", nil];
    });
    if (item.dependsRaw.length == 0) return @[];
    NSSet<NSString *> *installed = [self installedAndProvidedIDs];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *part in [item.dependsRaw componentsSeparatedByString:@","]) {
        NSString *dep = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange alt = [dep rangeOfString:@"|"];
        if (alt.location != NSNotFound) dep = [[dep substringToIndex:alt.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange paren = [dep rangeOfString:@"("];
        if (paren.location != NSNotFound) dep = [[dep substringToIndex:paren.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (dep.length == 0) continue;
        if ([virtualIDs containsObject:dep]) continue;
        if ([dep hasPrefix:@"gsc."] || [dep hasPrefix:@"cy+"]) continue;
        if ([dep isEqualToString:item.packageID]) continue;
        if (![installed containsObject:dep] && ![missing containsObject:dep]) {
            [missing addObject:dep];
        }
    }
    return [missing copy];
}

+ (NSArray<NSString *> *)blockingProblemsForItem:(TPBackupItem *)item {
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    if (![TPDpkg pathExistsAt:item.debPath]) {
        [problems addObject:@"Không thấy file .deb của bản backup này nữa."];
    }
    NSArray<NSString *> *missing = [self missingDependenciesForItem:item];
    if (missing.count > 0) {
        [problems addObject:[NSString stringWithFormat:@"Thiếu gói phụ thuộc: %@ — restore tại máy sẽ làm dpkg báo trạng thái lỗi, hãy dùng đường Sileo để nó tự kéo đủ.", [missing componentsJoinedByString:@", "]]];
    }
    return [problems copy];
}

+ (NSArray<NSString *> *)warningsForItem:(TPBackupItem *)item {
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    if (item.scriptNames.count > 0) {
        [warnings addObject:[NSString stringWithFormat:@"Gói có script cài đặt (%@) — restore tại máy KHÔNG chạy các script này. Nếu tweak cần script để hoàn tất cài đặt, hãy dùng đường Sileo.", [item.scriptNames componentsJoinedByString:@", "]]];
    }
    NSString *installedVersion = [self installedVersionForPackageID:item.packageID];
    if (installedVersion == nil) {
        [warnings addObject:@"Tweak này hiện chưa được cài trên máy — restore sẽ cài mới hoàn toàn."];
    } else if (TPCompareVersions(item.version, installedVersion) < 0) {
        [warnings addObject:[NSString stringWithFormat:@"Bản backup là %@, cũ hơn bản đang cài (%@) — đây là HẠ CẤP.", item.version, installedVersion]];
    }
    if (item.hasPrefs) {
        for (NSDictionary<NSString *, NSString *> *prefs in item.prefsBackups) {
            NSString *dest = prefs[@"source"];
            if (dest.length == 0 && prefs[@"domain"].length > 0) {
                dest = [TPDpkg prefsFilePathForDomain:prefs[@"domain"]];
            }
            if (dest.length > 0 && [TPDpkg pathExistsAt:dest]) {
                [warnings addObject:@"Thông số hiện tại của tweak sẽ bị ghi đè bằng thông số trong bản backup."];
                break;
            }
        }
    }
    return [warnings copy];
}

#pragma mark - Restore tại máy

+ (BOOL)restoreInApp:(TPBackupItem *)item progress:(void (^)(NSString *))progress error:(NSString **)errorMessage {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *blocking = [self blockingProblemsForItem:item];
    if (blocking.count > 0) {
        if (errorMessage) *errorMessage = [blocking componentsJoinedByString:@"\n"];
        [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:NO detail:[blocking firstObject] ?: @""];
        return NO;
    }

    if (progress) progress(@"Đang đọc file .deb…");
    NSError *readError = nil;
    TPDebReader *reader = [TPDebReader readerWithPath:item.debPath error:&readError];
    if (!reader) {
        NSString *message = [NSString stringWithFormat:@"Không đọc được file .deb: %@", readError.localizedDescription ?: @"lỗi không rõ"];
        if (errorMessage) *errorMessage = message;
        [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:NO detail:message];
        return NO;
    }
    // Kiểm tra trước: mọi file trong .deb phải có dữ liệu đọc được, tránh chép nửa vời.
    for (TPDebEntry *entry in reader.dataEntries) {
        if (entry.isFile && [reader dataForEntry:entry] == nil) {
            NSString *message = [NSString stringWithFormat:@"File trong .deb đọc không được: %@", entry.path];
            if (errorMessage) *errorMessage = message;
            [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:NO detail:message];
            return NO;
        }
    }

    // Sao lưu dpkg status trước khi đụng vào bất cứ thứ gì.
    NSString *snapshotDir = [[TPBackupManager backupRoot] stringByAppendingPathComponent:@"dpkg-snapshots"];
    [fm createDirectoryAtPath:snapshotDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *snapshotPath = [snapshotDir stringByAppendingPathComponent:[NSString stringWithFormat:@"status-%@", [formatter stringFromDate:[NSDate date]]]];
    [fm copyItemAtPath:[self dpkgStatusPath] toPath:snapshotPath error:nil];
    TPLog(@"Da sao luu dpkg status -> %@", snapshotPath);

    if (progress) progress(@"Đang chép file của tweak…");
    NSUInteger written = 0;
    NSUInteger skipped = 0;
    NSMutableArray<TPDebEntry *> *sorted = [reader.dataEntries mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(TPDebEntry *a, TPDebEntry *b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    for (TPDebEntry *entry in sorted) {
        NSString *dest = TPDestinationForDebPath(entry.path);
        if (entry.isDirectory) {
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            if (entry.mode > 0) {
                [fm setAttributes:@{ NSFilePosixPermissions: @(entry.mode) } ofItemAtPath:dest error:nil];
            }
            written++;
        } else if (entry.isLink) {
            [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dest error:nil];
            NSError *linkError = nil;
            if ([fm createSymbolicLinkAtPath:dest withDestinationPath:entry.linkTarget ?: @"" error:&linkError]) {
                written++;
            } else {
                skipped++;
                TPLog(@"Khong tao duoc symlink %@ -> %@: %@", dest, entry.linkTarget, linkError.localizedDescription);
            }
        } else if (entry.isFile) {
            NSData *data = [reader dataForEntry:entry];
            [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dest error:nil];
            if ([data writeToFile:dest atomically:NO]) {
                [fm setAttributes:@{ NSFilePosixPermissions: @(entry.mode > 0 ? entry.mode : 0644) } ofItemAtPath:dest error:nil];
                written++;
            } else {
                skipped++;
                TPLog(@"Khong ghi duoc file: %@", dest);
            }
        } else {
            skipped++;
        }
    }
    if (written == 0) {
        NSString *message = @"Không chép được file nào — có thể app không có quyền ghi vào thư mục hệ thống của máy.";
        if (errorMessage) *errorMessage = message;
        [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:NO detail:message];
        return NO;
    }

    if (progress) progress(@"Đang khôi phục thông số (prefs)…");
    NSString *prefsError = nil;
    if (item.hasPrefs) {
        [self restorePrefsOnly:item error:&prefsError];
        if (prefsError) TPLog(@"Restore prefs kem theo co loi: %@", prefsError);
    }

    if (progress) progress(@"Đang cập nhật cơ sở dữ liệu gói (dpkg)…");
    NSString *dpkgError = nil;
    if (![self updateDpkgForItem:item reader:reader error:&dpkgError]) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"Đã chép %lu file vào máy nhưng CHƯA ghi được dpkg (%@). Hãy cài chính file .deb này qua Sileo để hoàn tất — file đã nằm sẵn trong máy nên Sileo sẽ nhận ngay.", (unsigned long)written, dpkgError ?: @"lỗi không rõ"];
        }
        [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:NO detail:@"Chép file xong, ghi dpkg thất bại"];
        return NO;
    }

    NSString *detail = [NSString stringWithFormat:@"%@ — chép %lu mục, bỏ qua %lu", item.version, (unsigned long)written, (unsigned long)skipped];
    [TPBackupManager recordHistoryAction:@"Restore tại máy" packageID:item.packageID ok:YES detail:detail];
    TPLog(@"Restore tai may xong %@: %@", item.packageID, detail);
    return YES;
}

+ (BOOL)updateDpkgForItem:(TPBackupItem *)item reader:(TPDebReader *)reader error:(NSString **)errorMessage {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *infoDir = [TPDpkg dpkgInfoDirectory];

    // info/<id>.list
    NSMutableArray<NSString *> *listLines = [NSMutableArray array];
    for (TPDebEntry *entry in reader.dataEntries) {
        [listLines addObject:[@"/" stringByAppendingString:entry.path]];
    }
    NSString *listPath = [infoDir stringByAppendingPathComponent:[item.packageID stringByAppendingString:@".list"]];
    NSString *listText = [[listLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if (![listText writeToFile:listPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"không ghi được %@", listPath];
        return NO;
    }
    // info/<id>.<script> để Sileo gỡ/cập nhật sau này vẫn chạy đúng script.
    for (NSString *script in @[@"preinst", @"postinst", @"prerm", @"postrm"]) {
        NSData *data = [reader controlDataForEntryName:script];
        if (!data) continue;
        NSString *path = [infoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", item.packageID, script]];
        [data writeToFile:path atomically:NO];
        [fm setAttributes:@{ NSFilePosixPermissions: @0755 } ofItemAtPath:path error:nil];
    }

    // status: thay stanza của gói này bằng stanza trong .deb + dòng Status.
    NSString *controlText = [reader.controlText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (controlText.length == 0) {
        if (errorMessage) *errorMessage = @"file control trong .deb trống";
        return NO;
    }
    NSMutableArray<NSString *> *lines = [[controlText componentsSeparatedByString:@"\n"] mutableCopy];
    [lines insertObject:@"Status: install ok installed" atIndex:MIN((NSUInteger)1, lines.count)];
    NSString *newStanza = [lines componentsJoinedByString:@"\n"];

    NSString *statusPath = [self dpkgStatusPath];
    NSString *raw = [NSString stringWithContentsOfFile:statusPath encoding:NSUTF8StringEncoding error:nil];
    if (raw.length == 0) {
        if (errorMessage) *errorMessage = @"không đọc được dpkg status";
        return NO;
    }
    NSMutableArray<NSString *> *stanzas = [NSMutableArray array];
    BOOL replaced = NO;
    for (NSString *stanza in [raw componentsSeparatedByString:@"\n\n"]) {
        NSString *trimmed = [stanza stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSString *firstLine = [[trimmed componentsSeparatedByString:@"\n"] firstObject] ?: @"";
        if ([firstLine isEqualToString:[@"Package: " stringByAppendingString:item.packageID]]) {
            [stanzas addObject:newStanza];
            replaced = YES;
        } else {
            [stanzas addObject:trimmed];
        }
    }
    if (!replaced) [stanzas addObject:newStanza];
    NSString *newRaw = [[stanzas componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n"];
    NSError *writeError = nil;
    if (![newRaw writeToFile:statusPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"không ghi được dpkg status: %@", writeError.localizedDescription ?: @""];
        return NO;
    }
    return YES;
}

#pragma mark - Chỉ restore prefs

+ (BOOL)restorePrefsOnly:(TPBackupItem *)item error:(NSString **)errorMessage {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!item.hasPrefs) {
        if (errorMessage) *errorMessage = @"Bản backup này không có file prefs.";
        return NO;
    }
    NSString *sessionDir = [item sessionDirectory];
    NSUInteger done = 0;
    for (NSDictionary<NSString *, NSString *> *prefs in item.prefsBackups) {
        NSString *file = prefs[@"file"];
        // Bản 1.1.1 trở đi ghi sẵn đường dẫn gốc (source); manifest 1.1.0 chỉ có domain thì suy ra đường mặc định.
        NSString *dest = prefs[@"source"];
        if (dest.length == 0 && prefs[@"domain"].length > 0) {
            dest = [TPDpkg prefsFilePathForDomain:prefs[@"domain"]];
        }
        if (file.length == 0 || dest.length == 0) continue;
        NSString *src = [sessionDir stringByAppendingPathComponent:file];
        [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [fm removeItemAtPath:dest error:nil];
        NSError *copyError = nil;
        if ([fm copyItemAtPath:src toPath:dest error:&copyError]) {
            done++;
            TPLog(@"Da khoi phuc prefs -> %@", dest);
        } else {
            TPLog(@"Khong khoi phuc duoc prefs -> %@: %@", dest, copyError.localizedDescription);
        }
    }
    if (done == 0) {
        NSString *message = @"Không chép lại được file prefs nào.";
        if (errorMessage) *errorMessage = message;
        [TPBackupManager recordHistoryAction:@"Restore prefs" packageID:item.packageID ok:NO detail:message];
        return NO;
    }
    [TPBackupManager recordHistoryAction:@"Restore prefs" packageID:item.packageID ok:YES detail:[NSString stringWithFormat:@"%lu file prefs", (unsigned long)done]];
    return YES;
}

#pragma mark - Respring

+ (BOOL)attemptRespring {
    // SpringBoard chạy cùng user mobile với app — tìm PID rồi gửi SIGTERM.
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t length = 0;
    if (sysctl(mib, 4, NULL, &length, NULL, 0) == 0 && length > 0) {
        struct kinfo_proc *procs = malloc(length);
        if (procs != NULL) {
            if (sysctl(mib, 4, procs, &length, NULL, 0) == 0) {
                size_t count = length / sizeof(struct kinfo_proc);
                pid_t sbPid = -1;
                for (size_t i = 0; i < count; i++) {
                    if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
                        sbPid = procs[i].kp_proc.p_pid;
                        break;
                    }
                }
                free(procs);
                if (sbPid > 0 && kill(sbPid, SIGTERM) == 0) {
                    TPLog(@"Da gui SIGTERM cho SpringBoard (pid %d) de respring", (int)sbPid);
                    return YES;
                }
            } else {
                free(procs);
            }
        }
    }
    // Dự phòng: sbreload nếu máy có.
    for (NSString *candidate in @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload"]) {
        if (![TPDpkg pathExistsAt:candidate]) continue;
        pid_t pid = 0;
        const char *path = [candidate fileSystemRepresentation];
        char *const argv[] = { (char *)path, NULL };
        if (posix_spawn(&pid, path, NULL, NULL, argv, environ) == 0) {
            TPLog(@"Da chay sbreload: %@", candidate);
            return YES;
        }
    }
    TPLog(@"Khong respring tu dong duoc");
    return NO;
}

@end
