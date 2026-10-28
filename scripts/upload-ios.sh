#!/bin/zsh
# Builds the App Store version of Joshu for iPhone and uploads it to App Store Connect: it shows up in TestFlight a few
# minutes later, and from there it's submitted for review. Run it after scripts/release.sh, so it carries the same version.
#
# Needs, once, a small settings file outside the repo: ~/Library/Application Support/Joshu/app-store.json
#   {"team_id": "ABCDE12345", "key_id": "XXXXXXXXXX", "issuer_id": "xxxxxxxx-xxxx-…", "key_path": "/Users/…/AuthKey_XXXXXXXXXX.p8"}
# team_id: developer.apple.com › Membership. The key: App Store Connect › Users and Access › Integrations ›
# App Store Connect API › Generate (role App Manager); download the .p8 once and keep it somewhere safe.
set -euo pipefail
cd "$(dirname "$0")/.."

CONF="$HOME/Library/Application Support/Joshu/app-store.json"
[[ -f "$CONF" ]] || { echo "Missing $CONF (see the top of scripts/upload-ios.sh)."; exit 1; }
CFG=("${(@f)$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c["team_id"]); print(c["key_id"]); print(c["issuer_id"]); print(c["key_path"])' "$CONF")}")
TEAM=$CFG[1]; KEY_ID=$CFG[2]; ISSUER=$CFG[3]; KEY_PATH=$CFG[4]
[[ -f "$KEY_PATH" ]] || { echo "The App Store Connect key isn't at $KEY_PATH."; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")

# The App Store build: your paid team, Sign in with Apple, and (for the first versions) no Apple Watch app, which
# would need its own screenshots and review.
ORBIT_TEAM_ID="$TEAM" python3 scripts/gen-ios-project.py --app-store --no-watch >/dev/null
trap 'python3 scripts/gen-ios-project.py >/dev/null' EXIT   # back to the everyday project afterwards

rm -rf build/ios-appstore
mkdir -p build/ios-appstore
echo "Building the App Store version…"
xcodebuild -project iOS/Orbit.xcodeproj -scheme OrbitPhone -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios-appstore/Joshu.xcarchive "${AUTH[@]}" -quiet archive

cat > build/ios-appstore/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath build/ios-appstore/Joshu.xcarchive -exportOptionsPlist build/ios-appstore/ExportOptions.plist \
  -exportPath build/ios-appstore/export "${AUTH[@]}"
echo "Uploaded Joshu $(cat VERSION) for iPhone. It appears in App Store Connect › TestFlight in a few minutes."
