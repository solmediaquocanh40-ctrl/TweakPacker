#import <Foundation/Foundation.h>

@class TPBackupItem;

// Restore bản backup: đường 1 — ngay trên máy (chép file + chép prefs + ghi dpkg);
// đường 2 — qua Sileo do giao diện xử lý bằng bảng chia sẻ file .deb.
@interface TPRestoreManager : NSObject

// Các gói phụ thuộc (Depends) mà máy chưa có — rỗng nếu đủ.
+ (NSArray<NSString *> *)missingDependenciesForItem:(TPBackupItem *)item;
// Lý do KHÔNG được restore tại máy (thiếu phụ thuộc, mất file .deb...). Rỗng = restore được.
+ (NSArray<NSString *> *)blockingProblemsForItem:(TPBackupItem *)item;
// Cảnh báo nên biết trước khi restore tại máy (có script cài đặt, hạ cấp, ghi đè prefs...).
+ (NSArray<NSString *> *)warningsForItem:(TPBackupItem *)item;

// Restore tại máy. Tự sao lưu dpkg status trước khi ghi; ghi status ở bước cuối cùng.
+ (BOOL)restoreInApp:(TPBackupItem *)item
            progress:(void (^)(NSString *step))progress
               error:(NSString **)errorMessage;

// Chỉ chép lại các file prefs của bản backup, không đụng tới file tweak/dpkg.
+ (BOOL)restorePrefsOnly:(TPBackupItem *)item error:(NSString **)errorMessage;

// Thử respring: gửi tín hiệu cho SpringBoard (chạy cùng user mobile), dự phòng sbreload.
+ (BOOL)attemptRespring;

@end
