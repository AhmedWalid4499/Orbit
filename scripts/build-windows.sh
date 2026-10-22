#!/bin/zsh
# Builds the Windows installer into windows/dist: Orbit-Setup.exe plus latest.yml (read by the Windows app's updater).
# Needs Node.js, and Rosetta on Apple-silicon Macs (the installer packer, NSIS, only ships for Intel).
set -euo pipefail
cd "$(dirname "$0")/../windows"

VERSION="$(tr -d '[:space:]' < ../VERSION)"
if [[ "$(uname -m)" == "arm64" ]] && ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  echo "Rosetta is needed to build the Windows installer on this Mac: softwareupdate --install-rosetta --agree-to-license"
  exit 2
fi

[[ -d node_modules ]] || npm ci --no-audit --no-fund
npx electron-vite build
rm -rf dist
npx electron-builder --win --x64 --publish never -c.extraMetadata.version="$VERSION"
echo "Built windows/dist/Orbit-Setup.exe (version $VERSION)"
