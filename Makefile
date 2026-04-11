.PHONY: build clean lint open

# Open the project in Xcode
open:
	open MacSnitch.xcodeproj

# Build via xcodebuild (requires signing to be configured)
build:
	xcodebuild \
		-project MacSnitch.xcodeproj \
		-scheme MacSnitchApp \
		-configuration Debug \
		build

# Release build
release:
	xcodebuild \
		-project MacSnitch.xcodeproj \
		-scheme MacSnitchApp \
		-configuration Release \
		build

# Run SwiftLint (install with: brew install swiftlint)
lint:
	swiftlint lint --config .swiftlint.yml

# Clean derived data
clean:
	xcodebuild -project MacSnitch.xcodeproj -scheme MacSnitchApp clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/MacSnitch-*

# Enable System Extension developer mode (run once on dev machine, requires sudo)
dev-mode:
	systemextensionsctl developer on

# Unload the extension (useful during development)
unload-extension:
	systemextensionsctl uninstall com.macsnitch com.macsnitch.extension
