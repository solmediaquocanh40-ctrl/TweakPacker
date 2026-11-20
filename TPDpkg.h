#import <Foundation/Foundation.h>

@interface TPPackage : NSObject

@property (nonatomic, copy) NSString *packageID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *architecture;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, copy) NSString *shortDescription;
// Nguyên văn stanza trong dpkg status, đã bỏ trường Status và Conffiles — dùng làm file control khi đóng lại .deb.
@property (nonatomic, copy) NSString *controlText;
// Các đường dẫn file gói đã đăng ký khi cài (nguyên văn trong dpkg info/<id>.list).
@property (nonatomic, copy) NSArray<NSString *> *listedPaths;
@property (nonatomic, assign) BOOL isTweak;
@property (nonatomic, assign) unsigned long long totalSize;
@property (nonatomic, assign) NSUInteger fileCount;

@end

@interface TPDpkg : NSObject

// "" trên máy rootful, "/var/jb" trên máy rootless/roothide.
+ (NSString *)jbPrefix;
+ (NSString *)dpkgInfoDirectory;
+ (NSArray<TPPackage *> *)installedPackages;
// Kiểm tra tồn tại bằng lstat — thấy cả symlink gãy.
+ (BOOL)pathExistsAt:(NSString *)path;
// Đường dẫn thật trên đĩa của một dòng trong .list (thử nguyên văn, rồi thử thêm tiền tố jb).
+ (NSString *)realPathForListedPath:(NSString *)listedPath;
// Đường dẫn ghi vào trong .deb (bỏ "/" đầu và tiền tố var/jb nếu có).
+ (NSString *)debPathForListedPath:(NSString *)listedPath;

@end
