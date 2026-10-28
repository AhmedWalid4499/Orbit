#!/bin/zsh
# Builds the Dock tile plug-in (Dock/JoshuDock.m), which shows the Joshu Pro icon in the Dock even while Joshu is
# closed, and signs it into the app. Usage: scripts/build-dock.sh <path/to/Orbit.app> <signing identity or ->
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; IDENTITY="${2:--}"
PLUGIN="$APP/Contents/PlugIns/JoshuDock.docktileplugin"
mkdir -p "$PLUGIN/Contents/MacOS" "$PLUGIN/Contents/Resources"
cp Dock/Info.plist "$PLUGIN/Contents/Info.plist"
if [[ -f Support/AppIconPro-mac.png ]]; then cp Support/AppIconPro-mac.png "$PLUGIN/Contents/Resources/AppIconPro.png"; else echo "Support/AppIconPro-mac.png is missing: the Dock keeps the usual icon (make it with ORBIT_PRO_LOGO=…-mac.png)"; fi
xcrun clang -fobjc-arc -bundle -framework AppKit -arch arm64 -mmacosx-version-min=15.0 -o "$PLUGIN/Contents/MacOS/JoshuDock" Dock/JoshuDock.m
codesign --force --sign "$IDENTITY" "$PLUGIN"
