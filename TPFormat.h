#import <Foundation/Foundation.h>

// Định dạng dung lượng dùng chung: "512 KB" / "1.5 MB".
static inline NSString *TPSizeString(unsigned long long bytes) {
    double kb = (double)bytes / 1024.0;
    if (kb < 1024.0) return [NSString stringWithFormat:@"%.0f KB", kb];
    double mb = kb / 1024.0;
    if (mb < 1024.0) return [NSString stringWithFormat:@"%.1f MB", mb];
    return [NSString stringWithFormat:@"%.2f GB", mb / 1024.0];
}

// "02:15 21/11/2026"
static inline NSString *TPDateTimeString(NSDate *date) {
    if (!date) return @"";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm dd/MM/yyyy";
    });
    return [formatter stringFromDate:date];
}
