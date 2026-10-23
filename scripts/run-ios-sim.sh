#!/bin/zsh
# Builds the iPhone app for the simulator (signed locally, so the widgets' App Group works) and launches it.
# Pass -demo to use sample data instead of your account.
set -e
cd "$(dirname "$0")/.."
DD="${TMPDIR:-/tmp}/orbit-ios-sim"
xcodebuild -project iOS/Orbit.xcodeproj -scheme OrbitPhone -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet build
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Orbit.app"
xcrun simctl terminate booted com.ahmedwalid.orbit 2>/dev/null || true
xcrun simctl launch booted com.ahmedwalid.orbit "$@"
