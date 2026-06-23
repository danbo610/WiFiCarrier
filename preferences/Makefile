TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
# THEOS_PACKAGE_SCHEME is inherited from the top-level Makefile / command line
# (rootless or roothide) so the same source builds both.

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WiFiCarrier
WiFiCarrier_FILES = $(wildcard *.m)
WiFiCarrier_INSTALL_PATH = /Library/PreferenceBundles
WiFiCarrier_FRAMEWORKS = CoreGraphics UIKit MessageUI
# Preferences is a private framework with no link stub in the macOS Xcode SDK used on
# CI. We vendor a Preferences.tbd stub under Frameworks/ and link against it: -FFrameworks
# adds the local search path, PRIVATE_FRAMEWORKS pulls in -framework Preferences. This
# resolves PSListController/PSTableCell/PSSpecifier at LINK time (catches missing symbols,
# no "-undefined dynamic_lookup is deprecated" warning, deterministic across SDKs) instead
# of deferring to runtime. tbd's install-name points at the real system framework path.
WiFiCarrier_PRIVATE_FRAMEWORKS = Preferences
WiFiCarrier_LDFLAGS = -FFrameworks

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/WiFiCarrier.plist$(ECHO_END)
