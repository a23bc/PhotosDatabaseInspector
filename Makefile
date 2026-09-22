APP_NAME := PhotosDatabaseInspector
BUNDLE_ID := com.a23bc.PhotosDatabaseInspector
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
PAYLOAD_DIR := $(BUILD_DIR)/Payload
TIPA := $(BUILD_DIR)/$(APP_NAME).tipa
ENTITLEMENTS := $(APP_NAME).entitlements
TRASH_DIR := .trash/$(shell date +%Y%m%d%H%M%S)

SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := xcrun --sdk iphoneos clang
CFLAGS := -fobjc-arc -isysroot "$(SDK)" -miphoneos-version-min=15.0
LDFLAGS := -framework UIKit -framework Foundation -lsqlite3
CODESIGN := codesign --force --sign - --generate-entitlement-der --timestamp=none

SOURCES := \
	PhotosDatabaseInspector/AppDelegate.m \
	PhotosDatabaseInspector/ViewController.m \
	PhotosDatabaseInspector/Photos/PhotoDatabaseScanner.m \
	PhotosDatabaseInspector/Photos/PhotoDatabaseInspector.m

.PHONY: all clean sign verify package

all: $(APP_DIR)/$(APP_NAME)

$(APP_DIR)/$(APP_NAME): $(SOURCES) \
	PhotosDatabaseInspector/ViewController.h \
	PhotosDatabaseInspector/Photos/PhotoDatabaseScanner.h \
	PhotosDatabaseInspector/Photos/PhotoDatabaseInspector.h \
	PhotosDatabaseInspector/Info.plist \
	$(ENTITLEMENTS) build/embedded-entitlements.plist
	@mkdir -p "$(APP_DIR)"
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) \
		-Wl,-sectcreate,__TEXT,__entitlements,build/embedded-entitlements.plist \
		-o "$@"
	@cp PhotosDatabaseInspector/Info.plist "$(APP_DIR)/Info.plist"

build/embedded-entitlements.plist: $(ENTITLEMENTS)
	@mkdir -p "$(BUILD_DIR)"
	@cp "$<" "$@"

sign: all
	$(CODESIGN) --entitlements "$(ENTITLEMENTS)" "$(APP_DIR)"

verify: sign
	@codesign --verify --verbose=2 "$(APP_DIR)"
	@codesign --display --verbose=2 "$(APP_DIR)"
	@codesign --display --entitlements "$(BUILD_DIR)/granted.plist" --xml "$(APP_DIR)"
	@/usr/libexec/PlistBuddy -c "Print" "$(BUILD_DIR)/granted.plist"

package: verify
	@mkdir -p "$(TRASH_DIR)"
	@[ ! -e "$(PAYLOAD_DIR)" ] || mv "$(PAYLOAD_DIR)" "$(TRASH_DIR)/"
	@[ ! -e "$(TIPA)" ] || mv "$(TIPA)" "$(TRASH_DIR)/"
	@mkdir -p "$(PAYLOAD_DIR)"
	@cp -R "$(APP_DIR)" "$(PAYLOAD_DIR)/"
	@cd "$(BUILD_DIR)" && zip -qry "$(APP_NAME).tipa" Payload
	@echo "Created $(TIPA)"

clean:
	@mkdir -p "$(TRASH_DIR)"
	@[ ! -e "$(BUILD_DIR)" ] || mv "$(BUILD_DIR)" "$(TRASH_DIR)"
	@echo "Moved $(BUILD_DIR) to $(TRASH_DIR)"
