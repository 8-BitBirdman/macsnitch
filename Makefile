.PHONY: build release clean lint test open xcodeproj dev-mode unload-extension help

SCHEME_APP = MacSnitchApp
PROJECT    = MacSnitch.xcodeproj

xcodeproj:
	python3 Scripts/generate_xcodeproj.py

open:
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Debug build | xcpretty

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Release build | xcpretty

archive:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Release \
		-archivePath build/MacSnitch.xcarchive archive | xcpretty

test:
	swift test --package-path .

lint:
	swiftlint lint

format:
	swift-format format -r -i MacSnitchApp NetworkExtension Shared Tests

dev-mode:
	sudo systemextensionsctl developer on

prod-mode:
	sudo systemextensionsctl developer off

unload-extension:
	systemextensionsctl uninstall com.macsnitch com.macsnitch.extension

reset-rules:
	rm -f "$(HOME)/Library/Application Support/MacSnitch/macsnitch.sqlite"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_APP) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/MacSnitch-*
	rm -rf build/

help:
	@grep -E '^[a-zA-Z_-]+:' $(MAKEFILE_LIST) | awk -F: '{printf "\033[36m%-20s\033[0m\n", $$1}'
