#import <Foundation/Foundation.h>

// Ghi log gỡ lỗi ra /var/mobile/Documents/TweakPacker.log (dự phòng: thư mục Documents của app).
void TPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *TPLogFilePath(void);
