#import <Foundation/Foundation.h>

@class TPPackage;

// Một bản backup của một tweak trong kho.
@interface TPBackupItem : NSObject

@property (nonatomic, copy) NSString *sessionName;   // tên thư mục đợt backup; "" nếu là bản lẻ từ 1.0.0
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy) NSString *packageID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *debPath;
@property (nonatomic, assign) unsigned long long debSize;
// Các file prefs đã backup theo: [{domain, file}] — file nằm cùng thư mục với .deb.
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *prefsBackups;
// Danh sách file trong .deb: [{path, size, type}] — path dạng debPath.
@property (nonatomic, copy) NSArray<NSDictionary *> *fileList;
@property (nonatomic, copy) NSString *dependsRaw;
@property (nonatomic, copy) NSArray<NSString *> *scriptNames;
@property (nonatomic, assign) BOOL integrityOK;
@property (nonatomic, copy) NSString *integrityNote;
@property (nonatomic, assign) BOOL legacy;           // bản lẻ do 1.0.0 xuất, không có manifest

@property (nonatomic, readonly) BOOL hasPrefs;
@property (nonatomic, readonly) NSUInteger fileCount; // chỉ tính file + symlink
- (NSString *)sessionDirectory;

@end

@interface TPBackupManager : NSObject

// Thư mục gốc chứa mọi bản backup (= thư mục xuất file của TPDebBuilder).
+ (NSString *)backupRoot;
// Tạo thư mục cho một đợt backup mới: Backup-yyyyMMdd-HHmmss, trùng thì thêm -2, -3...
+ (NSString *)createSessionDirectory;

// Backup 1 gói vào thư mục đợt: đóng .deb + chép prefs + tự kiểm tra toàn vẹn + ghi manifest.
// progress nhận (mô tả bước, tỉ lệ 0..1) — có thể nil.
+ (TPBackupItem *)backupPackage:(TPPackage *)package
                    intoSession:(NSString *)sessionDirectory
                       progress:(void (^)(NSString *step, float fraction))progress
                          error:(NSString **)errorMessage;

// Quét toàn bộ kho, mới nhất xếp trước. Gồm cả bản lẻ .deb của 1.0.0 (legacy).
+ (NSArray<TPBackupItem *> *)allItems;
+ (BOOL)deleteItem:(TPBackupItem *)item error:(NSString **)errorMessage;
+ (unsigned long long)totalSizeOfItems:(NSArray<TPBackupItem *> *)items;

// Nhật ký hoạt động trong app.
+ (void)recordHistoryAction:(NSString *)action packageID:(NSString *)packageID ok:(BOOL)ok detail:(NSString *)detail;
+ (NSArray<NSDictionary *> *)historyEntries; // mới nhất trước

// So sánh 2 bản backup: {added: [path], removed: [path], changed: [{path, sizeA, sizeB}]}
+ (NSDictionary *)compareItem:(TPBackupItem *)a withItem:(TPBackupItem *)b;

@end
