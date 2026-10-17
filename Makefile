APP    := build/mymd.app
BIN    := $(APP)/Contents/MacOS/mymd
SRC    := $(wildcard Sources/*.swift)
PREFIX ?= /Applications

all: $(APP)

$(APP): $(SRC) Info.plist
	@mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -O -swift-version 5 -target arm64-apple-macos13 $(SRC) -o $(BIN)
	codesign --force -s - $(APP)

install: $(APP)
	rm -rf $(PREFIX)/mymd.app
	cp -R $(APP) $(PREFIX)/

clean:
	rm -rf build

.PHONY: all install clean
