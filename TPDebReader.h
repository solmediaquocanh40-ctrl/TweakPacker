#import <Foundation/Foundation.h>

// Một mục trong file tar (nằm trong control.tar.gz / data.tar.gz của .deb).
@interface TPDebEntry : NSObject

@property (nonatomic, copy) NSString *path;        // dạng debPath: không có "/" ở đầu, không có "./"
@property (nonatomic, assign) char type;           // '0' file, '5' thư mục, '2' symlink
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, assign) unsigned int mode;
@property (nonatomic, copy) NSString *linkTarget;  // chỉ có với symlink

@property (nonatomic, readonly) BOOL isFile;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly) BOOL isLink;

@end

// Đọc lại file .deb (định dạng ar + tar.gz do chính TweakPacker xuất ra, hoặc .deb nén gzip nói chung).
@interface TPDebReader : NSObject

+ (instancetype)readerWithPath:(NSString *)path error:(NSError **)error;

@property (nonatomic, readonly) NSString *debPath;
@property (nonatomic, readonly) NSString *controlText;
@property (nonatomic, readonly) NSArray<TPDebEntry *> *controlEntries;
@property (nonatomic, readonly) NSArray<TPDebEntry *> *dataEntries;

// Tên các script cài đặt có trong gói (preinst/postinst/prerm/postrm).
@property (nonatomic, readonly) NSArray<NSString *> *maintainerScriptNames;

- (NSData *)dataForEntry:(TPDebEntry *)entry;
- (NSData *)controlDataForEntryName:(NSString *)name;
// Trường trong file control (Package/Name/Version/Depends...), "" nếu không có.
- (NSString *)controlField:(NSString *)field;

@end
