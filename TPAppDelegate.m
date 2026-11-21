#import "TPAppDelegate.h"
#import "TPPackageListViewController.h"
#import "TPAppTweakViewController.h"
#import "TPBackupListViewController.h"
#import "TPHistoryViewController.h"
#import "TPSettingsViewController.h"
#import "TPTheme.h"

@implementation TPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    TPPackageListViewController *packages = [[TPPackageListViewController alloc] init];
    packages.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Đã cài" image:[UIImage systemImageNamed:@"list.bullet"] tag:0];
    UINavigationController *navPackages = [[UINavigationController alloc] initWithRootViewController:packages];

    TPAppTweakViewController *appTweak = [[TPAppTweakViewController alloc] init];
    UINavigationController *navAppTweak = [[UINavigationController alloc] initWithRootViewController:appTweak];

    TPBackupListViewController *backups = [[TPBackupListViewController alloc] init];
    UINavigationController *navBackups = [[UINavigationController alloc] initWithRootViewController:backups];

    TPHistoryViewController *history = [[TPHistoryViewController alloc] init];
    UINavigationController *navHistory = [[UINavigationController alloc] initWithRootViewController:history];

    TPSettingsViewController *settings = [[TPSettingsViewController alloc] init];
    UINavigationController *navSettings = [[UINavigationController alloc] initWithRootViewController:settings];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[navPackages, navAppTweak, navBackups, navHistory, navSettings];
    self.window.rootViewController = tabs;
    [TPTheme applyTintToWindow:self.window];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
