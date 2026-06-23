TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
# THEOS_PACKAGE_SCHEME is inherited from the top-level Makefile / command line
# (rootless or roothide) so the same source builds both.

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WiFiCarrier
WiFiCarrier_FILES = $(wildcard *.m)
WiFiCarrier_INSTALL_PATH = /Library/PreferenceBundles
WiFiCarrier_FRAMEWORKS = CoreGraphics UIKit MessageUI
# Preferences is a private framework with no link stub in the macOS Xcode SDK used
# on CI. Headers come from theos/headers; resolve PSListController / PSTableCell /
# PSSpecifier at runtime inside Settings.app via dynamic_lookup. -no_fixup_chains is
# required because the modern macOS linker forbids dynamic_lookup with arm64e chained fixups.
WiFiCarrier_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-no_fixup_chains

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/WiFiCarrier.plist$(ECHO_END)
