ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = CloudManager
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = TarabBannerForce
TarabBannerForce_FILES = Tweak.xm
TarabBannerForce_CFLAGS = -fobjc-arc
TarabBannerForce_FRAMEWORKS = Foundation UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
