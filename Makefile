
# Scheme is parameterized so CI can build both rootless and roothide from one source.
# Local default = rootless; override with: make package THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless
export THEOS_PACKAGE_SCHEME
export ARCHS = arm64 arm64e

# Native Xcode (latest) SDK on the macOS CI runner; deploy target 14.0 produces
# arm64e that loads on iOS 15/16 rootless + roothide jailbreaks.
TARGET = iphone:clang:latest:14.0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WiFiCarrier
WiFiCarrier_FILES = Tweak.xm iOS13.xm
WiFiCarrier_CFLAGS += -fobjc-arc -w
# Foundation/CoreFoundation are auto-linked by Theos; UIKit + SystemConfiguration
# (UILongPressGestureRecognizer / SCNetworkReachability*) linked explicitly.
WiFiCarrier_FRAMEWORKS = UIKit SystemConfiguration

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences

include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
