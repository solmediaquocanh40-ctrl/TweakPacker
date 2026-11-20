TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TweakPacker

TweakPacker_FILES = main.m TPAppDelegate.m TPLog.m TPDpkg.m TPDebBuilder.m TPPackageListViewController.m
TweakPacker_FRAMEWORKS = UIKit Foundation
TweakPacker_LIBRARIES = z
TweakPacker_CFLAGS = -fobjc-arc
TweakPacker_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
