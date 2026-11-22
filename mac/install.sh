#!/bin/bash
# Builds Flip Clock, installs it to /Applications and restarts its widget cleanly. Copying the app by
# hand leaves the old widget process and a second registered copy in build/, which can freeze the widget.
set -euo pipefail
cd "$(dirname "$0")"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEST="/Applications/Flip Clock.app"
PRODUCTS="$PWD/build/DerivedData/Build/Products/Release"

./build.sh
pkill -x "Flip Clock" || true
rm -rf "$DEST"
cp -R "build/Flip Clock.app" "$DEST"
for copy in "$PWD/build/Flip Clock.app" "$PRODUCTS/Flip Clock.app" "$PRODUCTS/FlipClockWidget.appex"; do
  "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
  rm -rf "$copy"
done
"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/FlipClockWidget.appex"
pkill -x FlipClockWidget || true
sleep 1
killall chronod 2>/dev/null || true
sleep 2
# macOS only trusts (and can read the widget settings of) an app that has been opened once since it was
# installed. Until then the widget draws its first few minutes, then freezes at its next refresh.
open -g -j "$DEST"
sleep 6
osascript -e 'quit app "Flip Clock"' >/dev/null 2>&1 || true
echo "Installed: $DEST"
