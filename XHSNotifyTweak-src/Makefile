# 小红书私信通 私信提醒插件（纯 dylib，无越狱依赖）
# 产物：.theos/obj/XHSNotifyTweak.dylib
#
# 本地编译需要：
#   macOS + Xcode + Theos（https://theos.dev）
#   或者直接用仓库里的 .github/workflows/build.yml 在 GitHub 上编译

TARGET := iphone:clang:latest:12.0
ARCHS := arm64 arm64e
DEBUG := 0
FINALPACKAGE := 1

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = XHSNotifyTweak

XHSNotifyTweak_FILES = \
	Hooks.m \
	NYConfig.m \
	NYNotifier.m \
	NYSettings.m

XHSNotifyTweak_CFLAGS = -fobjc-arc -O2
XHSNotifyTweak_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox UserNotifications CoreGraphics
XHSNotifyTweak_LDFLAGS = -Wl,-install_name,@rpath/XHSNotifyTweak.dylib
XHSNotifyTweak_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
