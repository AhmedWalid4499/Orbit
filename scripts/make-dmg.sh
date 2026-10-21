#!/bin/zsh
# Packs build/Orbit.app into build/Orbit.dmg: open it, drag Orbit into Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr --noqtn build/Orbit.app "$STAGE/Orbit.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me first.txt" <<'TXT'
Installing Orbit

1. Drag Orbit onto the Applications folder.
2. Open Applications and double-click Orbit.

If macOS says it can't check Orbit for malware, that's because Orbit isn't from the App Store:
open System Settings › Privacy & Security, scroll down, and click "Open Anyway" next to Orbit.
You only need to do this once; after that Orbit keeps itself up to date.
TXT

rm -f build/Orbit.dmg
hdiutil create -volname "Orbit" -srcfolder "$STAGE" -ov -format UDZO -quiet build/Orbit.dmg
IDENTITY="${ORBIT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | awk '{print $2}')}"
[[ -n "$IDENTITY" ]] && codesign --force --sign "$IDENTITY" build/Orbit.dmg
echo "Built build/Orbit.dmg"
