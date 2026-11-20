#import <Foundation/Foundation.h>

@class TPPackage;

@interface TPDebBuilder : NSObject

// Thư mục chứa các file .deb đã xuất: /var/mobile/Documents/TweakPacker (dự phòng: Documents của app).
+ (NSString *)outputDirectory;

// Đóng gói 1 tweak thành file .deb cài lại được. Trả về đường dẫn file, hoặc nil nếu lỗi.
+ (NSString *)buildDebForPackage:(TPPackage *)package
                       fileCount:(NSUInteger *)outFileCount
                         skipped:(NSUInteger *)outSkipped
                           error:(NSError **)error;

// Như trên nhưng ghi file .deb vào thư mục chỉ định (dùng cho các đợt backup theo phiên).
+ (NSString *)buildDebForPackage:(TPPackage *)package
                     toDirectory:(NSString *)directory
                       fileCount:(NSUInteger *)outFileCount
                         skipped:(NSUInteger *)outSkipped
                           error:(NSError **)error;

@end
