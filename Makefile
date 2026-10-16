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
	rm -rf "$(PREFIX)/Dealer.app"
	cp -R build/Dealer.app "$(PREFIX)/Dealer.app"
	$(LSREGISTER) -f "$(PREFIX)/Dealer.app"
	@echo "Installed $(PREFIX)/Dealer.app — open it, then choose \"Set Dealer as Default Browser…\" from its menu."

uninstall:
	-$(LSREGISTER) -u "$(PREFIX)/Dealer.app"
	rm -rf "$(PREFIX)/Dealer.app"

clean:
	rm -rf .build build
