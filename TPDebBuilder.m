#import "TPDebBuilder.h"
#import "TPDpkg.h"
#import "TPLog.h"
#include <sys/stat.h>
#include <unistd.h>
#import <zlib.h>

#pragma mark - Gzip (zlib)

static NSData *TPGzipData(NSData *data) {
    if (data.length == 0) return [NSData data];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    NSMutableData *output = [NSMutableData data];
    const NSUInteger chunkSize = 256 * 1024;
    NSUInteger offset = 0;
    int ret = Z_OK;
    while (ret != Z_STREAM_END) {
        NSUInteger remaining = data.length - offset;
        NSUInteger thisChunk = MIN(remaining, chunkSize);
        int flush = (offset + thisChunk >= data.length) ? Z_FINISH : Z_NO_FLUSH;
        stream.next_in = (Bytef *)data.bytes + offset;
        stream.avail_in = (uInt)thisChunk;
        offset += thisChunk;
        unsigned char outBuffer[64 * 1024];
        do {
            stream.next_out = outBuffer;
            stream.avail_out = (uInt)sizeof(outBuffer);
            ret = deflate(&stream, flush);
            if (ret == Z_STREAM_ERROR) {
                deflateEnd(&stream);
                return nil;
            }
            NSUInteger produced = sizeof(outBuffer) - stream.avail_out;
            if (produced > 0) [output appendBytes:outBuffer length:produced];
        } while (stream.avail_out == 0);
    }
    deflateEnd(&stream);
    return [output copy];
}

#pragma mark - Tar (ustar)

@interface TPTarWriter : NSObject
@property (nonatomic, strong) NSMutableData *data;
- (void)addEntryWithName:(NSString *)name mode:(unsigned int)mode type:(char)type linkName:(NSString *)linkName fileData:(NSData *)fileData mtime:(long long)mtime;
- (NSData *)finishedData;
@end

@interface TPTarWriter ()
- (void)appendOctal:(unsigned long long)value toBuffer:(unsigned char *)buffer width:(NSUInteger)width;
@end

@implementation TPTarWriter

- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [NSMutableData data];
    }
    return self;
}

- (void)appendOctal:(unsigned long long)value toBuffer:(unsigned char *)buffer width:(NSUInteger)width {
    char tmp[32];
    snprintf(tmp, sizeof(tmp), "%0*llo", (int)(width - 1), value);
    memcpy(buffer, tmp, width - 1);
    buffer[width - 1] = '\0';
}

- (void)addEntryWithName:(NSString *)name mode:(unsigned int)mode type:(char)type linkName:(NSString *)linkName fileData:(NSData *)fileData mtime:(long long)mtime {
    BOOL hasData = (type == '0' || type == 'L');

    NSString *entryName = name;
    NSString *prefix = @"";
    NSData *fullNameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (fullNameData.length > 100) {
        NSArray<NSString *> *parts = [name componentsSeparatedByString:@"/"];
        NSString *candidatePrefix = nil;
        NSString *candidateName = nil;
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *p = [[parts subarrayWithRange:NSMakeRange(0, i)] componentsJoinedByString:@"/"];
            NSString *n = [[parts subarrayWithRange:NSMakeRange(i, parts.count - i)] componentsJoinedByString:@"/"];
            if (p.length > 155) break;
            if (n.length <= 100) {
                candidatePrefix = p;
                candidateName = n;
                break;
            }
        }
        if (candidateName != nil) {
            entryName = candidateName;
            prefix = candidatePrefix;
        } else {
            // GNU longlink: một mục 'L' chứa tên đầy đủ, đứng ngay trước mục thật.
            NSMutableData *longData = [NSMutableData dataWithData:fullNameData];
            [longData appendBytes:"\0" length:1];
            [self addEntryWithName:@"././@LongLink" mode:0644 type:'L' linkName:nil fileData:longData mtime:mtime];
            entryName = [name substringToIndex:MIN((NSUInteger)100, name.length)];
        }
    }

    unsigned char header[512];
    memset(header, 0, sizeof(header));
    NSData *entryNameData = [entryName dataUsingEncoding:NSUTF8StringEncoding];
    memcpy(header + 0, entryNameData.bytes, MIN(entryNameData.length, (NSUInteger)100));
    [self appendOctal:mode toBuffer:header + 100 width:8];
    [self appendOctal:0 toBuffer:header + 108 width:8];
    [self appendOctal:0 toBuffer:header + 116 width:8];
    [self appendOctal:hasData ? (unsigned long long)fileData.length : 0 toBuffer:header + 124 width:12];
    [self appendOctal:(unsigned long long)mtime toBuffer:header + 136 width:12];
    memset(header + 148, ' ', 8);
    header[156] = (unsigned char)type;
    if (linkName.length > 0) {
        NSData *linkData = [linkName dataUsingEncoding:NSUTF8StringEncoding];
        memcpy(header + 157, linkData.bytes, MIN(linkData.length, (NSUInteger)100));
    }
    memcpy(header + 257, "ustar", 5);
    header[262] = '\0';
    header[263] = '0';
    header[264] = '0';
    memcpy(header + 265, "root", 4);
    memcpy(header + 297, "wheel", 5);
    [self appendOctal:0 toBuffer:header + 329 width:8];
    [self appendOctal:0 toBuffer:header + 337 width:8];
    if (prefix.length > 0) {
        NSData *prefixData = [prefix dataUsingEncoding:NSUTF8StringEncoding];
        memcpy(header + 345, prefixData.bytes, MIN(prefixData.length, (NSUInteger)155));
    }
    unsigned int sum = 0;
    for (int i = 0; i < 512; i++) sum += header[i];
    char checksum[8];
    snprintf(checksum, sizeof(checksum), "%06o", sum);
    memcpy(header + 148, checksum, 6);
    header[154] = '\0';
    header[155] = ' ';

    [self.data appendBytes:header length:512];
    if (hasData && fileData.length > 0) {
        [self.data appendData:fileData];
        NSUInteger pad = (512 - (fileData.length % 512)) % 512;
        if (pad > 0) {
            void *zeros = calloc(1, pad);
            [self.data appendBytes:zeros length:pad];
            free(zeros);
        }
    }
}

- (NSData *)finishedData {
    unsigned char zeros[1024];
    memset(zeros, 0, sizeof(zeros));
    [self.data appendBytes:zeros length:sizeof(zeros)];
    return [self.data copy];
}

@end

#pragma mark - Ar (.deb)

static void TPArAppendMember(NSMutableData *archive, NSString *name, NSData *content) {
    unsigned char header[60];
    memset(header, ' ', sizeof(header));
    NSData *nameData = [name dataUsingEncoding:NSASCIIStringEncoding];
    memcpy(header + 0, nameData.bytes, MIN(nameData.length, (NSUInteger)16));
    char number[24];
    snprintf(number, sizeof(number), "%llu", (unsigned long long)[[NSDate date] timeIntervalSince1970]);
    memcpy(header + 16, number, strlen(number));
    memcpy(header + 28, "0", 1);
    memcpy(header + 34, "0", 1);
    memcpy(header + 40, "100644", 6);
    snprintf(number, sizeof(number), "%llu", (unsigned long long)content.length);
    memcpy(header + 48, number, strlen(number));
    header[58] = '`';
    header[59] = '\n';
    [archive appendBytes:header length:60];
    [archive appendData:content];
    if (content.length % 2 == 1) {
        unsigned char newline = '\n';
        [archive appendBytes:&newline length:1];
    }
}

#pragma mark - TPDebBuilder

@implementation TPDebBuilder

+ (NSString *)outputDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *primary = @"/var/mobile/Documents/TweakPacker";
        [[NSFileManager defaultManager] createDirectoryAtPath:primary withIntermediateDirectories:YES attributes:nil error:nil];
        if ([[NSFileManager defaultManager] isWritableFileAtPath:primary]) {
            dir = primary;
        } else {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            dir = [docs stringByAppendingPathComponent:@"TweakPacker"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        TPLog(@"Thu muc xuat file: %@", dir);
    });
    return dir;
}

+ (NSString *)buildDebForPackage:(TPPackage *)package fileCount:(NSUInteger *)outFileCount skipped:(NSUInteger *)outSkipped error:(NSError **)error {
    NSUInteger packed = 0;
    NSUInteger skipped = 0;

    // ---------- data.tar.gz ----------
    TPTarWriter *dataTar = [[TPTarWriter alloc] init];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *listed in package.listedPaths) {
        NSString *debPath = [TPDpkg debPathForListedPath:listed];
        if (debPath.length == 0) continue;
        NSString *real = [TPDpkg realPathForListedPath:listed];
        if (!real) {
            skipped++;
            continue;
        }
        struct stat st;
        if (lstat([real fileSystemRepresentation], &st) != 0) {
            skipped++;
            continue;
        }
        unsigned int mode = (unsigned int)(st.st_mode & 07777);
        if (S_ISDIR(st.st_mode)) {
            NSString *dirName = [debPath hasSuffix:@"/"] ? debPath : [debPath stringByAppendingString:@"/"];
            if ([seen containsObject:dirName]) continue;
            [seen addObject:dirName];
            [dataTar addEntryWithName:dirName mode:mode type:'5' linkName:nil fileData:nil mtime:(long long)st.st_mtime];
        } else if (S_ISLNK(st.st_mode)) {
            char linkBuffer[1024];
            ssize_t n = readlink([real fileSystemRepresentation], linkBuffer, sizeof(linkBuffer) - 1);
            if (n <= 0) {
                skipped++;
                continue;
            }
            linkBuffer[n] = '\0';
            NSString *target = [NSString stringWithUTF8String:linkBuffer];
            if (target.length > 100) {
                TPLog(@"Bo qua symlink co dich qua dai: %@ -> %@", listed, target);
                skipped++;
                continue;
            }
            if ([seen containsObject:debPath]) continue;
            [seen addObject:debPath];
            [dataTar addEntryWithName:debPath mode:mode type:'2' linkName:target fileData:nil mtime:(long long)st.st_mtime];
            packed++;
        } else if (S_ISREG(st.st_mode)) {
            if ([seen containsObject:debPath]) continue;
            [seen addObject:debPath];
            NSData *content = [NSData dataWithContentsOfFile:real];
            if (!content) {
                skipped++;
                continue;
            }
            [dataTar addEntryWithName:debPath mode:mode type:'0' linkName:nil fileData:content mtime:(long long)st.st_mtime];
            packed++;
        } else {
            skipped++;
        }
    }
    if (packed == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"TweakPacker" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Gói không có file nào đọc được" }];
        }
        if (outSkipped) *outSkipped = skipped;
        return nil;
    }
    NSData *dataTarGz = TPGzipData([dataTar finishedData]);
    if (!dataTarGz) {
        if (error) {
            *error = [NSError errorWithDomain:@"TweakPacker" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Nén data.tar.gz thất bại" }];
        }
        return nil;
    }

    // ---------- control.tar.gz ----------
    TPTarWriter *controlTar = [[TPTarWriter alloc] init];
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    NSData *controlData = [package.controlText dataUsingEncoding:NSUTF8StringEncoding];
    [controlTar addEntryWithName:@"./control" mode:0644 type:'0' linkName:nil fileData:controlData mtime:now];
    NSString *infoDir = [TPDpkg dpkgInfoDirectory];
    for (NSString *script in @[@"preinst", @"postinst", @"prerm", @"postrm"]) {
        NSString *path = [infoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", package.packageID, script]];
        NSData *scriptData = [NSData dataWithContentsOfFile:path];
        if (scriptData) {
            [controlTar addEntryWithName:[@"./" stringByAppendingString:script] mode:0755 type:'0' linkName:nil fileData:scriptData mtime:now];
        }
    }
    NSString *conffilesPath = [infoDir stringByAppendingPathComponent:[package.packageID stringByAppendingString:@".conffiles"]];
    NSData *conffilesData = [NSData dataWithContentsOfFile:conffilesPath];
    if (conffilesData) {
        [controlTar addEntryWithName:@"./conffiles" mode:0644 type:'0' linkName:nil fileData:conffilesData mtime:now];
    }
    NSData *controlTarGz = TPGzipData([controlTar finishedData]);
    if (!controlTarGz) {
        if (error) {
            *error = [NSError errorWithDomain:@"TweakPacker" code:3 userInfo:@{ NSLocalizedDescriptionKey: @"Nén control.tar.gz thất bại" }];
        }
        return nil;
    }

    // ---------- .deb (ar) ----------
    NSMutableData *deb = [NSMutableData data];
    [deb appendData:[@"!<arch>\n" dataUsingEncoding:NSASCIIStringEncoding]];
    TPArAppendMember(deb, @"debian-binary/", [@"2.0\n" dataUsingEncoding:NSASCIIStringEncoding]);
    TPArAppendMember(deb, @"control.tar.gz/", controlTarGz);
    TPArAppendMember(deb, @"data.tar.gz/", dataTarGz);

    NSMutableString *safeVersion = [NSMutableString string];
    for (NSUInteger i = 0; i < package.version.length; i++) {
        unichar c = [package.version characterAtIndex:i];
        BOOL okChar = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '+' || c == '-' || c == '~';
        if (okChar) {
            [safeVersion appendFormat:@"%C", c];
        } else {
            [safeVersion appendString:@"_"];
        }
    }
    NSString *fileName = [NSString stringWithFormat:@"%@_%@.deb", package.packageID, safeVersion];
    NSString *outPath = [[self outputDirectory] stringByAppendingPathComponent:fileName];
    if (![deb writeToFile:outPath atomically:YES]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TweakPacker" code:4 userInfo:@{ NSLocalizedDescriptionKey: @"Ghi file .deb thất bại" }];
        }
        return nil;
    }

    if (outFileCount) *outFileCount = packed;
    if (outSkipped) *outSkipped = skipped;
    TPLog(@"Da xuat %@ -> %@ (%lu file, bo qua %lu muc)", package.packageID, fileName, (unsigned long)packed, (unsigned long)skipped);
    return outPath;
}

@end
