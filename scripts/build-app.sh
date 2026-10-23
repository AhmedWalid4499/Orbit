#!/bin/zsh
# Builds and signs Orbit.app into ./build. Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Orbit"

# Assemble and sign in a temp folder, then copy into build/: an iCloud-synced Desktop adds file attributes
# that make codesign refuse bundles with extensions inside.
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP="$STAGE_DIR/Orbit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Orbit"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Version comes from the VERSION file; the build number is the git commit count.
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/Supabase.json "$APP/Contents/Resources/Supabase.json" # sync project (publishable key only)
mkdir -p "$APP/Contents/Resources/Tour" && cp Support/Tour/*.jpg "$APP/Contents/Resources/Tour/" # first-launch tour screenshots

# Siri & Shortcuts: extract App Intents metadata the way Xcode does, from the compiler's constant values.
CONF_DIR="$( [[ "$CONFIG" == "release" ]] && echo Release || echo Debug )"
CONSTS=".build/out/Intermediates.noindex/Orbit.build/$CONF_DIR/Orbit-p.build/Objects-normal/arm64"
INTENTS_TMP="$STAGE_DIR/intents"; mkdir -p "$INTENTS_TMP"
find "$PWD/Sources/Orbit" -name "*.swift" > "$INTENTS_TMP/sources.txt"
ls "$PWD/$CONSTS"/*.swiftconstvalues > "$INTENTS_TMP/consts.txt"
TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swift)")")"
xcrun appintentsmetadataprocessor --output "$INTENTS_TMP" --toolchain-dir "$TOOLCHAIN" --module-name Orbit \
  --sdk-root "$(xcrun --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
  --platform-family macOS --deployment-target 15.0 --target-triple arm64-apple-macos15.0 \
  --source-file-list "$INTENTS_TMP/sources.txt" --swift-const-vals-list "$INTENTS_TMP/consts.txt" \
  --binary-file "$BIN" --quiet-warnings >/dev/null 2>&1
cp -R "$INTENTS_TMP/Metadata.appintents" "$APP/Contents/Resources/Metadata.appintents"
# If the owner chose (in Orbit › Settings) to share their Google setup, build it in so others can sign in without Google Cloud.
SHARED_GOOGLE="$HOME/Library/Application Support/Orbit/shared-google-client.json"
[[ -f "$SHARED_GOOGLE" ]] && cp "$SHARED_GOOGLE" "$APP/Contents/Resources/GoogleClient.json" && echo "Included shared Google sign-in"

# Sign with a stable identity so macOS (Keychain, privacy permissions) treats every build as the same app.
# Override with ORBIT_SIGN_IDENTITY; falls back to ad-hoc signing if no Apple Development certificate exists.
IDENTITY="${ORBIT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | awk '{print $2}')}"
xattr -cr "$APP" # Finder/quarantine attributes make codesign refuse the bundle
# Desktop widgets live in a signed extension inside the app; it has to be signed before the app itself.
scripts/build-widgets.sh "$APP" "${IDENTITY:--}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier com.personal.orbit "$APP"
  echo "Signed with $(codesign -dvv "$APP" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2)"
else
  codesign --force --sign - "$APP"
  echo "No Apple Development certificate found; signed ad-hoc"
fi
rm -rf build/Orbit.app
mkdir -p build
ditto --norsrc --noextattr --noqtn "$APP" build/Orbit.app
echo "Built build/Orbit.app (version $VERSION, build $BUILD)"
