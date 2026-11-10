#!/bin/bash
# Builds "Flip Clock.app" (with its desktop widget) into mac/build. Needs Xcode and xcodegen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"

"$XCODEGEN" generate --quiet
rm -rf "build/Flip Clock.app"
xcodebuild -project FlipClock.xcodeproj -scheme FlipClock -configuration Release \
  -derivedDataPath build/DerivedData -quiet build
cp -R "build/DerivedData/Build/Products/Release/Flip Clock.app" build/
echo "Built: $PWD/build/Flip Clock.app"
