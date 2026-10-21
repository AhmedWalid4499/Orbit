#!/bin/zsh
# Builds and signs Orbit.app into ./build. Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Orbit"

APP="build/Orbit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Orbit"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Version comes from the VERSION file; the build number is the git commit count.
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/Supabase.json "$APP/Contents/Resources/Supabase.json" # sync project (publishable key only)
# If the owner chose (in Orbit › Settings) to share their Google setup, build it in so others can sign in without Google Cloud.
SHARED_GOOGLE="$HOME/Library/Application Support/Orbit/shared-google-client.json"
[[ -f "$SHARED_GOOGLE" ]] && cp "$SHARED_GOOGLE" "$APP/Contents/Resources/GoogleClient.json" && echo "Included shared Google sign-in"

# Sign with a stable identity so macOS (Keychain, privacy permissions) treats every build as the same app.
# Override with ORBIT_SIGN_IDENTITY; falls back to ad-hoc signing if no Apple Development certificate exists.
IDENTITY="${ORBIT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | awk '{print $2}')}"
xattr -cr "$APP" # Finder/quarantine attributes make codesign refuse the bundle
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier com.personal.orbit "$APP"
  echo "Signed with $(codesign -dvv "$APP" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2)"
else
  codesign --force --sign - "$APP"
  echo "No Apple Development certificate found; signed ad-hoc"
fi
echo "Built $APP (version $VERSION, build $BUILD)"
