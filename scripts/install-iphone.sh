#!/bin/zsh
# Builds Orbit for iPhone and installs it on your connected iPhone.
# With a free Apple account, Apple makes the app stop opening after 7 days: just run this again.
#
# Before the first run:
#   1. Xcode › Settings › Accounts: add your Apple ID (ahmedwalid4499@gmail.com).
#   2. Connect the iPhone with a cable, unlock it and tap "Trust" on "Trust This Computer?".
#   3. On the iPhone: Settings › Privacy & Security › Developer Mode › On (it restarts).
# After the first install: Settings › General › VPN & Device Management › your Apple ID › Trust.
set -e
cd "$(dirname "$0")/.."

JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
UDID="$(python3 - "$JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and hw.get("deviceType") == "iPhone":
        print(hw.get("udid", "")); break
EOF
)"
rm -f "$JSON"
if [[ -z "$UDID" ]]; then
  echo "No iPhone found. Connect it with a cable, unlock it, and tap Trust on the iPhone, then run this again."
  exit 1
fi
echo "Installing on iPhone $UDID…"

build() {
  xcodebuild -project iOS/Orbit.xcodeproj -scheme OrbitPhone -configuration Release \
    -destination "id=$UDID" -derivedDataPath build/ios \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build 2>&1 | tee build/ios-build.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
  grep -q "BUILD SUCCEEDED" build/ios-build.log
}

mkdir -p build
if ! build; then
  if grep -qiE "app group|personal development team" build/ios-build.log; then
    # Free accounts can't use App Groups, which the home-screen widgets need: install without widgets.
    echo "Your Apple account can't give widgets access to Orbit's data, so installing without widgets."
    python3 scripts/gen-ios-project.py --no-widgets >/dev/null
    trap 'python3 scripts/gen-ios-project.py >/dev/null' EXIT
    build || { echo "Build failed. Details: build/ios-build.log"; exit 1; }
  else
    echo "Build failed. Details: build/ios-build.log"
    exit 1
  fi
fi

APP="build/ios/Build/Products/Release-iphoneos/Orbit.app"
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" com.ahmedwalid.orbit >/dev/null 2>&1 || \
  echo "Installed. If it doesn't open: Settings › General › VPN & Device Management › trust your Apple ID, then tap Orbit."
echo "Done. Orbit is on your iPhone (good for 7 days; run scripts/install-iphone.sh again to renew)."
