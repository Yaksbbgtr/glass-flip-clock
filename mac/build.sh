#!/bin/bash
# Builds "Flip Clock.app" into mac/build. Needs Xcode (or the Command Line Tools) installed.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Flip Clock.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

echo "Compiling…"
swiftc -O -target arm64-apple-macos13 -framework AppKit -framework WebKit -framework ServiceManagement -o build/FlipClock-arm64 Sources/main.swift
swiftc -O -target x86_64-apple-macos13 -framework AppKit -framework WebKit -framework ServiceManagement -o build/FlipClock-x86_64 Sources/main.swift
lipo -create build/FlipClock-arm64 build/FlipClock-x86_64 -output "$APP/Contents/MacOS/FlipClock"
rm build/FlipClock-arm64 build/FlipClock-x86_64

cp Info.plist "$APP/Contents/Info.plist"
cp ../index.html "$APP/Contents/Resources/web/"
cp -R ../fonts "$APP/Contents/Resources/web/fonts"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"
echo "Built: $PWD/$APP"
