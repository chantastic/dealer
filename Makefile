PREFIX ?= $(HOME)/Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build test app dmg zip package icons install uninstall clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

# Drag-to-Applications disk image of the current build/Dealer.app.
dmg: app
	./scripts/make-dmg.sh

zip: app
	rm -f build/Dealer.zip
	ditto -c -k --sequesterRsrc --keepParent build/Dealer.app build/Dealer.zip

# Everything a release ships: universal app, zip, dmg, checksums (notarized when credentials are set).
package:
	./scripts/package-release.sh

# Regenerate Resources/AppIcon.iconset and the menu-bar PNGs from Assets/logo/*.svg.
icons:
	./scripts/generate-icons.sh

install: app
	mkdir -p "$(PREFIX)"
	rm -rf "$(PREFIX)/Dealer.app"
	cp -R build/Dealer.app "$(PREFIX)/Dealer.app"
	$(LSREGISTER) -f "$(PREFIX)/Dealer.app"
	@echo "Installed $(PREFIX)/Dealer.app — open it, then choose \"Set Dealer as Default Browser…\" from its menu."

uninstall:
	-$(LSREGISTER) -u "$(PREFIX)/Dealer.app"
	rm -rf "$(PREFIX)/Dealer.app"

clean:
	rm -rf .build build
