APP    := build/mymd.app
BIN    := $(APP)/Contents/MacOS/mymd
SRC    := $(wildcard Sources/*.swift)
ICNS   := build/AppIcon.icns
PREFIX ?= /Applications
BINDIR ?= $(HOME)/.local/bin

all: $(APP)

$(APP): $(SRC) Info.plist $(ICNS)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	swiftc -O -swift-version 5 -target arm64-apple-macos13 $(SRC) -o $(BIN)
	codesign --force -s - $(APP)

$(ICNS): tools/make-icon.swift
	@rm -rf build/AppIcon.iconset
	swift tools/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICNS)

install: $(APP)
	rm -rf $(PREFIX)/mymd.app
	cp -R $(APP) $(PREFIX)/
	@mkdir -p $(BINDIR)
	install -m 755 bin/mymd $(BINDIR)/mymd

clean:
	rm -rf build

.PHONY: all install clean
