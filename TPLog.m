#import "TPLog.h"

NSString *TPLogFilePath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *primary = @"/var/mobile/Documents/TweakPacker.log";
        NSString *dir = [primary stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (![[NSFileManager defaultManager] fileExistsAtPath:primary]) {
            [[NSData data] writeToFile:primary atomically:NO];
        }
        if ([[NSFileManager defaultManager] isWritableFileAtPath:primary]) {
            path = primary;
        } else {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            path = [docs stringByAppendingPathComponent:@"TweakPacker.log"];
        }
    });
    return path;
}

void TPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = TPLogFilePath();

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSData data] writeToFile:path atomically:NO];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
    NSLog(@"[TweakPacker] %@", message);
}
