#!/bin/zsh
# Builds Joshu for Android into build/Joshu.apk: the Windows app's screens plus android/src,
# in a Capacitor shell (android/native). Version comes from VERSION.
#
# Needs a JDK 21 and the Android SDK. Without them on the PATH it uses ~/.local/android-tools (jdk-21*/, sdk/),
# which this script sets up the first time (no admin password needed).
# The release key is ~/Library/Application Support/Joshu/android/joshu-release.keystore and its password is in the
# Keychain ("Joshu Android keystore"). Keep both: an update signed with a different key won't install over the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$HOME/.local/android-tools"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
IFS=. read -r MAJ MIN PAT <<< "$VERSION"
CODE=$(( MAJ * 10000 + MIN * 100 + PAT ))

# MARK: Toolchain
if ! /usr/libexec/java_home -v 21 >/dev/null 2>&1 && [[ -z "${JAVA_HOME:-}" ]]; then
  if ! ls -d "$TOOLS"/jdk-21*/Contents/Home >/dev/null 2>&1; then
    echo "Downloading a JDK 21 (Temurin) into $TOOLS…"
    mkdir -p "$TOOLS"
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/21/ga/mac/$( [[ $(uname -m) == arm64 ]] && echo aarch64 || echo x64 )/jdk/hotspot/normal/eclipse" | tar xz -C "$TOOLS"
  fi
  export JAVA_HOME="$(ls -d "$TOOLS"/jdk-21*/Contents/Home | head -1)"
fi
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
export ANDROID_HOME="${ANDROID_HOME:-$TOOLS/sdk}"
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "Downloading the Android command-line tools into $ANDROID_HOME…"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/cmd.zip" "https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip"
  unzip -q "$tmp/cmd.zip" -d "$tmp" && mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" && rm -rf "$tmp"
fi
if [[ ! -d "$ANDROID_HOME/platforms/android-35" || ! -d "$ANDROID_HOME/build-tools/35.0.0" ]]; then
  yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
  "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-35" "build-tools;35.0.0" >/dev/null
fi

# MARK: Release key (made once, kept outside the repo)
KEYDIR="$HOME/Library/Application Support/Joshu/android"
KEYSTORE="$KEYDIR/joshu-release.keystore"
if ! PASS="$(security find-generic-password -s "Joshu Android keystore" -w 2>/dev/null)"; then
  [[ -f "$KEYSTORE" ]] && { echo "The keystore exists but its password isn't in the Keychain. Restore it before building."; exit 1; }
  PASS="$(openssl rand -base64 24 | tr -d '/+=')"
  security add-generic-password -s "Joshu Android keystore" -a joshu -w "$PASS"
fi
if [[ ! -f "$KEYSTORE" ]]; then
  mkdir -p "$KEYDIR"
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KEYSTORE" -alias joshu -keyalg RSA -keysize 4096 -validity 36500 \
    -storepass "$PASS" -keypass "$PASS" -dname "CN=Joshu, O=Ahmed Walid" >/dev/null
  echo "Made the Android release key: $KEYSTORE"
fi

# MARK: Web bundle → native project → APK
cd "$ROOT/android"
[[ -d node_modules ]] || npm ci --no-audit --no-fund
npx tsc --noEmit -p tsconfig.json
npx vite build
npx cap sync android
cd native
echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew --quiet assembleRelease -PorbitVersionName="$VERSION" -PorbitVersionCode="$CODE" \
  -PorbitKeystore="$KEYSTORE" -PorbitKeystorePassword="$PASS"
mkdir -p "$ROOT/build"
cp app/build/outputs/apk/release/app-release.apk "$ROOT/build/Joshu.apk"
echo "Built build/Joshu.apk (Joshu $VERSION, version code $CODE)"
