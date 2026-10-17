APP    := build/mymd.app
BIN    := $(APP)/Contents/MacOS/mymd
SRC    := $(wildcard Sources/*.swift)
ICNS   := build/AppIcon.icns
TARGET := arm64-apple-macos13
PREFIX ?= /Applications
BINDIR ?= $(HOME)/.local/bin

MATH_SRC := $(wildcard Vendor/SwiftMath/Sources/*.swift)
MATH_LIB := build/math/libSwiftMath.a

all: $(APP)

$(APP): $(SRC) $(MATH_LIB) Info.plist $(ICNS) Resources/shortcuts.md $(wildcard Vendor/SwiftMath/mathFonts.bundle/*)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/shortcuts.md $(APP)/Contents/Resources/
	rm -rf $(APP)/Contents/Resources/mathFonts.bundle
	cp -R Vendor/SwiftMath/mathFonts.bundle $(APP)/Contents/Resources/
	swiftc -O -swift-version 5 -target $(TARGET) -I build/math -L build/math -lSwiftMath $(SRC) -o $(BIN)
	codesign --force -s - $(APP)

$(MATH_LIB): $(MATH_SRC)
	@mkdir -p build/math
	swiftc -O -swift-version 5 -target $(TARGET) -parse-as-library -module-name SwiftMath \
		-emit-library -static -emit-module -emit-module-path build/math/SwiftMath.swiftmodule \
		$(MATH_SRC) -o $(MATH_LIB)

$(ICNS): tools/make-icon.swift
	@rm -rf build/AppIcon.iconset
	swift tools/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICNS)

install: $(APP)
	rm -rf $(PREFIX)/mymd.app
	cp -R $(APP) $(PREFIX)/
	@mkdir -p $(BINDIR)
	install -m 755 bin/mymd $(BINDIR)/mymd

# Removes the app and the CLI. `make uninstall PURGE=1` also deletes settings,
# caches and saved window state.
uninstall:
	-@pkill -x mymd 2>/dev/null || true
	rm -rf $(PREFIX)/mymd.app
	rm -f $(BINDIR)/mymd
ifdef PURGE
	-defaults delete com.thuanngo.mymd 2>/dev/null
	rm -rf $(HOME)/Library/Caches/com.thuanngo.mymd
	rm -rf "$(HOME)/Library/Saved Application State/com.thuanngo.mymd.savedState"
endif

clean:
	rm -rf build

.PHONY: all install uninstall clean

# README screenshots: render docs/showcase.md in both themes and frame them.
SHOT_SIZE := 820x660
screenshots: $(APP)
	@mkdir -p build/shots
	@for theme in light dark; do \
		MYMD_APPEARANCE=$$theme MYMD_SNAPSHOT_SIZE=$(SHOT_SIZE) MYMD_SNAPSHOT=$(CURDIR)/build/shots/$$theme.pdf \
			$(BIN) docs/showcase.md && \
		swift tools/frame-shot.swift build/shots/$$theme.pdf docs/screenshots/$$theme.png && \
		echo "docs/screenshots/$$theme.png"; \
	done

.PHONY: screenshots
