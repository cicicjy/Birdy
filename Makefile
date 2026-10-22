APP_NAME=Birdy
BUILD=.build/release/Suibiancha
APP=dist/$(APP_NAME).app
CODESIGN_IDENTITY ?= Birdy Local Signing

.PHONY: build icon app clean
build:
	swift build -c release

icon:
	sh Scripts/build_icon.sh

app: build icon
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BUILD)" "$(APP)/Contents/MacOS/Suibiancha"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	mkdir -p "$(APP)/Contents/Resources"
	cp Resources/Birdy.icns "$(APP)/Contents/Resources/Birdy.icns"
	cp Resources/Birdy-menu.png "$(APP)/Contents/Resources/Birdy-menu.png"
	cp -R BrowserExtension "$(APP)/Contents/Resources/BrowserExtension"
	cp -R Resources/ArticlePractice "$(APP)/Contents/Resources/ArticlePractice"
	/usr/bin/codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP)"

clean:
	swift package clean
	rm -rf dist
