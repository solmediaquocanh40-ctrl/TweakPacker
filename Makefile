TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TweakPacker

TweakPacker_FILES = main.m TPAppDelegate.m TPLog.m TPDpkg.m TPDebBuilder.m TPDebReader.m TPBackupManager.m TPRestoreManager.m TPProgressHUD.m TPTheme.m TPInjectMap.m TPPackageListViewController.m TPAppTweakViewController.m TPDetailViewController.m TPFileListViewController.m TPBackupListViewController.m TPBackupItemViewController.m TPCompareViewController.m TPHistoryViewController.m TPSettingsViewController.m
TweakPacker_FRAMEWORKS = UIKit Foundation PhotosUI
TweakPacker_LIBRARIES = z
TweakPacker_CFLAGS = -fobjc-arc
TweakPacker_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
