#import <UIKit/UIKit.h>
#import "TPAppDelegate.h"
#import "TPLog.h"

// Ghi lại mọi exception không được xử lý vào file log trước khi app văng,
// để lần sau mở log ra là thấy ngay văng ở đâu, vì sao.
static void TPUncaughtExceptionHandler(NSException *exception) {
    TPLog(@"CRASH (exception): %@ — %@\nStack:\n%@", exception.name, exception.reason,
          [exception.callStackSymbols componentsJoinedByString:@"\n"]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&TPUncaughtExceptionHandler);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TPAppDelegate class]));
    }
}
