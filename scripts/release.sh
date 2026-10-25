#!/bin/zsh
# Publishes a new Orbit version to GitHub Releases, where the in-app updater picks it up.
#
#   scripts/release.sh 1.2.0 "What changed"      # notes are optional; defaults to commit subjects since the last release
#
# Needs a GitHub token with "Contents: Read and write" on AhmedWalid4499/Orbit, stored once in the login keychain:
#   security add-generic-password -s orbit-github-release -a AhmedWalid4499 -w
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="AhmedWalid4499/Orbit"
VERSION="${1:?Usage: scripts/release.sh <version> [notes]}"
TAG="v$VERSION"

TOKEN="$(security find-generic-password -s orbit-github-release -w 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  echo "No GitHub release token found. Create a fine-grained token for $REPO with Contents: Read and write, then run:"
  echo "  security add-generic-password -s orbit-github-release -a AhmedWalid4499 -w"
  exit 1
fi
api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

if curl -fsS -o /dev/null "https://api.github.com/repos/$REPO/releases/tags/$TAG" 2>/dev/null; then
  echo "$TAG is already published. Pick a higher version."; exit 1
fi

ZIP="build/Orbit-$VERSION.zip"
if git rev-parse "$TAG" >/dev/null 2>&1; then
  # Tagged by an earlier run that failed before publishing: rebuild that exact commit's state and finish.
  echo "Resuming $TAG (already tagged, not yet published)"
  [[ "$(git rev-parse HEAD)" == "$(git rev-list -n1 "$TAG")" ]] || { echo "HEAD has moved past $TAG; use a new version."; exit 1; }
  PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
else
  PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
NOTES="${2:-$(git log --pretty='- %s' ${PREV_TAG:+$PREV_TAG..HEAD} | grep -v '^- Release v' || true)}"

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  # Stamp the version and commit everything that's going out.
  echo "$VERSION" > VERSION
  # The website shows the version even when GitHub's API can't be reached.
  sed -i '' -E "s/(data-version>Free · Version )[0-9.]+/\\1$VERSION/g; s/(data-version-short>v)[0-9.]+/\\1$VERSION/g" docs/index.html
  git add -A
  git commit -m "Release $TAG" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" >/dev/null || true
  git tag -a "$TAG" -m "Orbit $VERSION"
fi

scripts/build-app.sh release
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr --noqtn build/Orbit.app "$ZIP"
git push origin HEAD --follow-tags

BODY="$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": "Orbit " + sys.argv[2], "body": sys.argv[3]}))' "$TAG" "$VERSION" "$NOTES")"
RELEASE_ID="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
api -X POST -H "Content-Type: application/zip" --data-binary @"$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=Orbit-$VERSION.zip" >/dev/null
# Installer for new people: always named Orbit.dmg so .../releases/latest/download/Orbit.dmg stays the same link.
scripts/make-dmg.sh
api -X POST -H "Content-Type: application/x-apple-diskimage" --data-binary @build/Orbit.dmg \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=Orbit.dmg" >/dev/null

# Windows: installer for new people (always Orbit-Setup.exe) plus latest.yml and the blockmap for the in-app updater.
# ORBIT_SKIP_WINDOWS=1 releases the Mac only: the previous release's Windows files are carried over unchanged,
# so the Windows updater still finds latest.yml and simply sees no new version.
if [[ -n "${ORBIT_SKIP_WINDOWS:-}" ]]; then
  PREV="$(api "https://api.github.com/repos/$REPO/releases?per_page=10" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    if r["tag_name"] != sys.argv[1] and any(a["name"] == "latest.yml" for a in r["assets"]):
        print(r["tag_name"]); break' "$TAG")"
  TMPW="$(mktemp -d)"
  for f in Orbit-Setup.exe Orbit-Setup.exe.blockmap latest.yml; do
    curl -fsSL -o "$TMPW/$f" "https://github.com/$REPO/releases/download/$PREV/$f"
    case "$f" in *.exe) type=application/vnd.microsoft.portable-executable;; *.yml) type=text/yaml;; *) type=application/octet-stream;; esac
    api -X POST -H "Content-Type: $type" --data-binary @"$TMPW/$f" \
      "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$f" >/dev/null
  done
  rm -rf "$TMPW"
  echo "Windows: kept $PREV's installer (no Windows update in this release)."
elif scripts/build-windows.sh; then
  for f in Orbit-Setup.exe Orbit-Setup.exe.blockmap latest.yml; do
    case "$f" in *.exe) type=application/vnd.microsoft.portable-executable;; *.yml) type=text/yaml;; *) type=application/octet-stream;; esac
    api -X POST -H "Content-Type: $type" --data-binary @"windows/dist/$f" \
      "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$f" >/dev/null
  done
  echo "Windows: https://github.com/$REPO/releases/latest/download/Orbit-Setup.exe"
else
  echo "Skipped the Windows build (see message above); the Mac release is published."
fi

echo "Published Orbit $VERSION: https://github.com/$REPO/releases/tag/$TAG"
echo "Installer: https://github.com/$REPO/releases/latest/download/Orbit.dmg"
