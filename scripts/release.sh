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
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "$TAG already exists. Pick a higher version."; exit 1
fi

PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
NOTES="${2:-$(git log --pretty='- %s' ${PREV_TAG:+$PREV_TAG..HEAD} | grep -v '^- Release v' || true)}"

# Stamp the version and commit everything that's going out.
echo "$VERSION" > VERSION
git add -A
git commit -m "Release $TAG" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" >/dev/null || true

scripts/build-app.sh release
ZIP="build/Orbit-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Orbit.app "$ZIP"

git tag -a "$TAG" -m "Orbit $VERSION"
git push origin HEAD --follow-tags

api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

BODY="$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": "Orbit " + sys.argv[2], "body": sys.argv[3]}))' "$TAG" "$VERSION" "$NOTES")"
RELEASE_ID="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
api -X POST -H "Content-Type: application/zip" --data-binary @"$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=Orbit-$VERSION.zip" >/dev/null

echo "Published Orbit $VERSION: https://github.com/$REPO/releases/tag/$TAG"
