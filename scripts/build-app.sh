#!/bin/sh
# Builds build/Tree Yard.app with SwiftPM. Needs only the Command Line Tools, not Xcode.
# Pass "debug" for a build with the development hooks, at build/Tree Yard Debug.app.
set -eu
cd "$(dirname "$0")/.."

# The macOS 27 SDK makes @State a macro whose plugin ships only with Xcode.
# With just the Command Line Tools, build against the macOS 26 SDK instead.
CLT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
if ! xcodebuild -version >/dev/null 2>&1 && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TreeYard"
APP="build/Tree Yard.app"
if [ "$CONFIG" = debug ]; then APP="build/Tree Yard Debug.app"; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TreeYard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fraunces.ttf "$APP/Contents/Resources/Fraunces.ttf"
cp Resources/Fraunces-OFL.txt "$APP/Contents/Resources/Fraunces-OFL.txt"

# The icon is drawn by the app itself, then packed into an .icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$BIN" --render-icon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon-1024.png

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
