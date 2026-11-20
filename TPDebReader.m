#import "TPDebReader.h"
#import "TPLog.h"
#import <zlib.h>

@implementation TPDebEntry

- (BOOL)isFile { return self.type == '0'; }
- (BOOL)isDirectory { return self.type == '5'; }
- (BOOL)isLink { return self.type == '2'; }

@end

#pragma mark - Gunzip (zlib)

static NSData *TPGunzipData(NSData *data) {
    if (data.length == 0) return nil;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, 15 + 16) != Z_OK) return nil;
    NSMutableData *output = [NSMutableData data];
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    unsigned char buffer[128 * 1024];
    int ret = Z_OK;
    while (ret != Z_STREAM_END) {
        stream.next_out = buffer;
        stream.avail_out = (uInt)sizeof(buffer);
        ret = inflate(&stream, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR) {
            inflateEnd(&stream);
            return nil;
        }
        NSUInteger produced = sizeof(buffer) - stream.avail_out;
        if (produced > 0) [output appendBytes:buffer length:produced];
        if (ret == Z_BUF_ERROR && produced == 0) break;
    }
    inflateEnd(&stream);
    return [output copy];
}

#pragma mark - Tar (đọc)

static unsigned long long TPOctalValue(const unsigned char *field, NSUInteger length) {
    char buffer[32];
    NSUInteger n = MIN(length, (NSUInteger)sizeof(buffer) - 1);
    memcpy(buffer, field, n);
    buffer[n] = '\0';
    return strtoull(buffer, NULL, 8);
}

static NSString *TPStringFromField(const unsigned char *field, NSUInteger length) {
    NSUInteger n = 0;
    while (n < length && field[n] != '\0') n++;
    return [[NSString alloc] initWithBytes:field length:n encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *TPNormalizeTarPath(NSString *path) {
    NSString *p = path;
    while ([p hasPrefix:@"./"]) p = [p substringFromIndex:2];
    if ([p hasPrefix:@"/"]) p = [p substringFromIndex:1];
    return p;
}

@interface TPTarListing : NSObject
@property (nonatomic, strong) NSMutableArray<TPDebEntry *> *entries;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *fileData;
@end

@implementation TPTarListing
@end

static TPTarListing *TPParseTar(NSData *tarData) {
    TPTarListing *listing = [[TPTarListing alloc] init];
    listing.entries = [NSMutableArray array];
    listing.fileData = [NSMutableDictionary dictionary];
    const unsigned char *bytes = tarData.bytes;
    NSUInteger total = tarData.length;
    NSUInteger offset = 0;
    NSString *pendingLongName = nil;
    while (offset + 512 <= total) {
        const unsigned char *header = bytes + offset;
        BOOL allZero = YES;
        for (int i = 0; i < 512; i++) {
            if (header[i] != 0) { allZero = NO; break; }
        }
        if (allZero) break;

        NSString *name = TPStringFromField(header + 0, 100);
        unsigned long long size = TPOctalValue(header + 124, 12);
        unsigned int mode = (unsigned int)TPOctalValue(header + 100, 8);
        char type = (char)header[156];
        if (type == '\0') type = '0';
        NSString *linkName = TPStringFromField(header + 157, 100);
        NSString *prefix = TPStringFromField(header + 345, 155);
        if (prefix.length > 0) name = [prefix stringByAppendingFormat:@"/%@", name];

        NSUInteger dataOffset = offset + 512;
        NSUInteger paddedSize = (NSUInteger)((size + 511) / 512) * 512;

        if (type == 'L') {
            // GNU longlink: dữ liệu là tên đầy đủ của mục ngay sau.
            if (dataOffset + size <= total) {
                pendingLongName = [[NSString alloc] initWithBytes:bytes + dataOffset length:(NSUInteger)size encoding:NSUTF8StringEncoding];
                pendingLongName = [pendingLongName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0"]];
            }
        } else if (type == 'x' || type == 'g') {
            // Header mở rộng pax — bỏ qua, không chứa file thật.
        } else {
            if (pendingLongName.length > 0) {
                name = pendingLongName;
                pendingLongName = nil;
            }
            TPDebEntry *entry = [[TPDebEntry alloc] init];
            entry.path = TPNormalizeTarPath(name);
            if (type == '5' && [entry.path hasSuffix:@"/"]) {
                entry.path = [entry.path substringToIndex:entry.path.length - 1];
            }
            entry.type = type;
            entry.size = size;
            entry.mode = mode;
            entry.linkTarget = linkName;
            if (entry.path.length > 0) {
                [listing.entries addObject:entry];
                if (entry.isFile && dataOffset + size <= total) {
                    listing.fileData[entry.path] = [NSData dataWithBytes:bytes + dataOffset length:(NSUInteger)size];
                }
            }
        }
        offset = dataOffset + paddedSize;
    }
    return listing;
}

#pragma mark - Ar (đọc)

static NSDictionary<NSString *, NSData *> *TPParseAr(NSData *data, NSError **error) {
    NSString *magic = [[NSString alloc] initWithBytes:data.bytes length:MIN((NSUInteger)8, data.length) encoding:NSASCIIStringEncoding];
    if (![magic isEqualToString:@"!<arch>\n"]) {
        if (error) *error = [NSError errorWithDomain:@"TweakPacker" code:10 userInfo:@{ NSLocalizedDescriptionKey: @"File không đúng định dạng .deb (ar)" }];
        return nil;
    }
    NSMutableDictionary<NSString *, NSData *> *members = [NSMutableDictionary dictionary];
    const unsigned char *bytes = data.bytes;
    NSUInteger total = data.length;
    NSUInteger offset = 8;
    while (offset + 60 <= total) {
        const unsigned char *header = bytes + offset;
        if (header[58] != '`' || header[59] != '\n') break;
        NSString *name = TPStringFromField(header + 0, 16);
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name hasSuffix:@"/"]) name = [name substringToIndex:name.length - 1];
        // Trường size của ar là số thập phân.
        char sizeBuffer[16];
        memcpy(sizeBuffer, header + 48, 10);
        sizeBuffer[10] = '\0';
        unsigned long long size = strtoull(sizeBuffer, NULL, 10);
        NSUInteger dataOffset = offset + 60;
        if (dataOffset + size > total) break;
        members[name] = [NSData dataWithBytes:bytes + dataOffset length:(NSUInteger)size];
        offset = dataOffset + (NSUInteger)size + (size % 2 == 1 ? 1 : 0);
    }
    return [members copy];
}

#pragma mark - TPDebReader

@interface TPDebReader ()
@property (nonatomic, copy) NSString *debPath;
@property (nonatomic, copy) NSString *controlText;
@property (nonatomic, copy) NSArray<TPDebEntry *> *controlEntries;
@property (nonatomic, copy) NSArray<TPDebEntry *> *dataEntries;
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *controlFileData;
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *dataFileData;
- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error;
- (NSData *)tarDataFromMember:(NSData *)member name:(NSString *)name error:(NSError **)error;
@end

@implementation TPDebReader

+ (instancetype)readerWithPath:(NSString *)path error:(NSError **)error {
    TPDebReader *reader = [[TPDebReader alloc] init];
    if (![reader loadFromPath:path error:error]) return nil;
    return reader;
}

- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error {
    self.debPath = path;
    NSData *raw = [NSData dataWithContentsOfFile:path];
    if (raw.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"TweakPacker" code:11 userInfo:@{ NSLocalizedDescriptionKey: @"Không đọc được file .deb" }];
        return NO;
    }
    NSDictionary<NSString *, NSData *> *members = TPParseAr(raw, error);
    if (!members) return NO;

    NSData *controlMember = nil;
    NSData *dataMember = nil;
    NSString *controlName = nil;
    NSString *dataName = nil;
    for (NSString *name in members) {
        if ([name hasPrefix:@"control.tar"]) { controlMember = members[name]; controlName = name; }
        if ([name hasPrefix:@"data.tar"]) { dataMember = members[name]; dataName = name; }
    }
    if (!controlMember || !dataMember) {
        if (error) *error = [NSError errorWithDomain:@"TweakPacker" code:12 userInfo:@{ NSLocalizedDescriptionKey: @"File .deb thiếu control.tar hoặc data.tar" }];
        return NO;
    }
    NSData *controlTar = [self tarDataFromMember:controlMember name:controlName error:error];
    if (!controlTar) return NO;
    NSData *dataTar = [self tarDataFromMember:dataMember name:dataName error:error];
    if (!dataTar) return NO;

    TPTarListing *controlListing = TPParseTar(controlTar);
    TPTarListing *dataListing = TPParseTar(dataTar);
    self.controlEntries = [controlListing.entries copy];
    self.dataEntries = [dataListing.entries copy];
    self.controlFileData = [controlListing.fileData copy];
    self.dataFileData = [dataListing.fileData copy];

    NSData *controlData = self.controlFileData[@"control"];
    self.controlText = controlData ? [[NSString alloc] initWithData:controlData encoding:NSUTF8StringEncoding] : @"";
    return YES;
}

- (NSData *)tarDataFromMember:(NSData *)member name:(NSString *)name error:(NSError **)error {
    if ([name hasSuffix:@".gz"]) {
        NSData *tar = TPGunzipData(member);
        if (!tar) {
            if (error) *error = [NSError errorWithDomain:@"TweakPacker" code:13 userInfo:@{ NSLocalizedDescriptionKey: @"Giải nén gzip trong .deb thất bại" }];
            return nil;
        }
        return tar;
    }
    if ([name hasSuffix:@".tar"]) return member;
    if (error) {
        *error = [NSError errorWithDomain:@"TweakPacker" code:14 userInfo:@{ NSLocalizedDescriptionKey: @"Bản .deb này dùng kiểu nén khác (xz/zstd) — TweakPacker hiện chỉ đọc được .deb nén gzip, mọi bản backup do TweakPacker tạo đều là gzip." }];
    }
    return nil;
}

- (NSData *)dataForEntry:(TPDebEntry *)entry {
    return self.dataFileData[entry.path];
}

- (NSData *)controlDataForEntryName:(NSString *)name {
    return self.controlFileData[name];
}

- (NSArray<NSString *> *)maintainerScriptNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (TPDebEntry *entry in self.controlEntries) {
        NSString *last = entry.path.lastPathComponent;
        if ([@[@"preinst", @"postinst", @"prerm", @"postrm"] containsObject:last]) {
            [names addObject:last];
        }
    }
    return [names copy];
}

- (NSString *)controlField:(NSString *)field {
    NSString *prefix = [field stringByAppendingString:@": "];
    for (NSString *line in [self.controlText componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:prefix]) {
            return [line substringFromIndex:prefix.length];
        }
    }
    return @"";
}

@end
