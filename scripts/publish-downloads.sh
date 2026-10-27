#!/bin/zsh
# Puts the latest Mac and Android installers on the website, at ahmedwalid4499.github.io/download/Joshu.dmg and
# /download/Joshu.apk, so the site's download buttons never point anywhere else. They live in the root-site checkout
# (the AhmedWalid4499.github.io repository, which also holds Google's site verification file).
#   scripts/publish-downloads.sh [path/to/Joshu.apk]   (without an APK, the one already on the site stays)
set -e
cd "$(dirname "$0")/.."
SITE=root-site
[[ -d $SITE/.git ]] || { echo "No root-site checkout: the website downloads weren't updated."; exit 0; }
mkdir -p $SITE/download
cp build/Orbit.dmg $SITE/download/Joshu.dmg
[[ -n "${1:-}" && -f "$1" ]] && cp "$1" $SITE/download/Joshu.apk
cd $SITE
git add -A
git diff --cached --quiet && { echo "Website downloads already up to date."; exit 0; }
git commit -q -m "Latest Joshu installers"
git push -q origin main
echo "Website downloads: https://ahmedwalid4499.github.io/download/Joshu.dmg$([[ -f download/Joshu.apk ]] && echo ' and /download/Joshu.apk')"
