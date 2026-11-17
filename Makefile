TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = YouTube

ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTMod

YTMod_FILES = Sources/Tweak.x Sources/Settings.x Sources/SettingsUI.x Sources/L10n.x Sources/SponsorBlock.x Sources/SignInFix.x Sources/Downloader.x Sources/SigDecipher.x Sources/Muxer.x
YTMod_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
YTMod_FRAMEWORKS = UIKit Foundation AVKit AVFoundation MediaPlayer Photos JavaScriptCore Security
YTMod_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

before-package::
	mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/YTMod"
	cp -R Resources/YTModResources.bundle "$(THEOS_STAGING_DIR)/Library/Application Support/YTMod/"

after-install::
	install.exec "killall -9 YouTube || true"
