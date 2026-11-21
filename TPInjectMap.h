#import <Foundation/Foundation.h>

// Một tweak đã chích (hoặc khai báo sẽ chích) vào đâu đó trong máy.
@interface TPInjectedTweak : NSObject

@property (nonatomic, copy) NSString *displayName;                    // tên gói nếu tra được qua dpkg, không thì tên dylib
@property (nonatomic, copy) NSString *dylibName;                      // tên dylib không đuôi, vd "uYou"
@property (nonatomic, copy, nullable) NSString *packageID;
@property (nonatomic, copy, nullable) NSString *packageVersion;
@property (nonatomic, assign) BOOL disabled;                          // dylib đã bị đổi tên .disabled
@property (nonatomic, assign) BOOL embedded;                          // dylib nhúng sẵn trong app (sideload), không qua substrate
@property (nonatomic, assign) BOOL systemWide;                        // lọc theo UIKit/Foundation = mọi app
@property (nonatomic, assign) BOOL classBased;                        // lọc theo class, không gắn được vào app cụ thể
@property (nonatomic, copy) NSArray<NSString *> *targets;             // chuỗi hiển thị các đích đến
@property (nonatomic, copy) NSArray<NSString *> *targetBundleIDs;     // bundle id đích (nếu khai theo Bundles)

@end

// Một app (hoặc SpringBoard) và các tweak đang chích vào nó.
@interface TPAppInjectEntry : NSObject

@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *iconPath;
@property (nonatomic, assign) BOOL isSpringBoard;
@property (nonatomic, copy) NSArray<TPInjectedTweak *> *tweaks;

@end

// Bản đồ App <-> Tweak xây từ: filter plist của từng tweak (DynamicLibraries/TweakInject),
// đối chiếu dpkg để ra tên gói, danh sách app đã cài (LSApplicationWorkspace),
// và quét dylib rời nhúng trong các app người dùng (dạng .ipa đã chích sẵn).
@interface TPInjectMap : NSObject

@property (nonatomic, copy) NSArray<TPAppInjectEntry *> *appEntries;      // chỉ app có tweak; SpringBoard đứng đầu
@property (nonatomic, copy) NSArray<TPInjectedTweak *> *systemWideTweaks;
@property (nonatomic, copy) NSArray<TPInjectedTweak *> *classTweaks;
@property (nonatomic, copy) NSArray<TPInjectedTweak *> *allTweaks;

// Chạy nền, completion gọi trên main queue.
+ (void)buildWithCompletion:(void (^)(TPInjectMap *map))completion;

@end
