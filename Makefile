SCHEME       = GMac
PROJECT      = GMac.xcodeproj
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData
RELEASE_APP  = $(shell find $(DERIVED_DATA)/GMac-* -name "GMac.app" -path "*/Release/*" 2>/dev/null | head -1)
INSTALL_DIR  = /Applications

.PHONY: build install clean

build:
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -destination 'platform=macOS' \
	  build

install: build
	rm -rf $(INSTALL_DIR)/GMac.app
	cp -R "$(RELEASE_APP)" $(INSTALL_DIR)/GMac.app
	xattr -dr com.apple.quarantine $(INSTALL_DIR)/GMac.app
	@echo "✓ GMac installé dans $(INSTALL_DIR)"
	open $(INSTALL_DIR)/GMac.app

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
