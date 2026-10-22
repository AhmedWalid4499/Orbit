#!/bin/zsh
# Builds Orbit's WidgetKit extension into <app>/Contents/PlugIns/OrbitWidgets.appex and signs it.
# SwiftPM can't build app extensions, so this compiles Widgets/ directly. Usage: scripts/build-widgets.sh build/Orbit.app <identity>
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; IDENTITY="${2:--}"
SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -target arm64-apple-macos15.0 -sdk "$SDK" -O -parse-as-library -application-extension \
  -module-name OrbitWidgets Widgets/OrbitWidgets.swift -o "$OUT/OrbitWidgets" \
  -Xlinker -e -Xlinker _NSExtensionMain  # extensions start in Foundation's NSExtensionMain (as Xcode links them), not Swift's main

# Assemble and sign in a temp folder: folders like an iCloud-synced Desktop add attributes codesign rejects.
STAGE="$OUT/OrbitWidgets.appex"
mkdir -p "$STAGE/Contents/MacOS"
cp "$OUT/OrbitWidgets" "$STAGE/Contents/MacOS/OrbitWidgets"
cp Widgets/Info.plist "$STAGE/Contents/Info.plist"
VERSION="$(tr -d '[:space:]' < VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGE/Contents/Info.plist"
xattr -cr "$STAGE"
codesign --force --sign "$IDENTITY" --entitlements Widgets/OrbitWidgets.entitlements "$STAGE"

APPEX="$APP/Contents/PlugIns/OrbitWidgets.appex"
rm -rf "$APPEX"
mkdir -p "$APP/Contents/PlugIns"
ditto --norsrc --noextattr --noqtn "$STAGE" "$APPEX"
echo "Built widgets"
