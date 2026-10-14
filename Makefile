PREFIX ?= $(HOME)/Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build test app install uninstall clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

install: app
	mkdir -p "$(PREFIX)"
	rm -rf "$(PREFIX)/Earl.app"
	cp -R build/Earl.app "$(PREFIX)/Earl.app"
	$(LSREGISTER) -f "$(PREFIX)/Earl.app"
	@echo "Installed $(PREFIX)/Earl.app — open it, then choose \"Set Earl as Default Browser…\" from its menu."

uninstall:
	-$(LSREGISTER) -u "$(PREFIX)/Earl.app"
	rm -rf "$(PREFIX)/Earl.app"

clean:
	rm -rf .build build
