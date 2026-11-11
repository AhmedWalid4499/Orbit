#!/bin/zsh
# Sets up Sign in with Apple for Joshu's account server (Supabase). Run it in Terminal after making the Services ID and
# the key on developer.apple.com (see SIGN_IN_WITH_APPLE.md):
#
#   scripts/setup-apple-signin.sh ~/Downloads/AuthKey_ABC123DEFG.p8 ABC123DEFG
#
# It makes the "Secret Key" Supabase asks for (a token signed with your key, valid 6 months; Apple's limit), copies it
# to the clipboard to paste in Supabase › Authentication › Apple, and stores the key as server secrets so deleting an
# account also ends its Sign in with Apple link. The key never goes in the app or the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
P8="${1:?Usage: scripts/setup-apple-signin.sh <AuthKey_XXXX.p8> <Key ID>}"
KEY_ID="${2:?Usage: scripts/setup-apple-signin.sh <AuthKey_XXXX.p8> <Key ID>}"
TEAM="${ORBIT_TEAM_ID:-Y2K55S3UA9}"
SERVICES_ID="${APPLE_SERVICES_ID:-com.ahmedwalid.orbit.signin}"
[[ -f "$P8" ]] || { echo "Can't find the key at: $P8"; exit 1; }
if command -v supabase >/dev/null; then supabase() { command supabase "$@"; }; else supabase() { npx --yes supabase@2 "$@"; }; fi
REF=$(python3 -c "import json,re;print(re.search(r'https://([a-z0-9]+)\.supabase', json.load(open('Support/Supabase.json'))['url']).group(1))")

# ES256 token: iss = team, sub = Services ID, aud = Apple, 180 days (Apple allows at most 6 months).
SECRET=$(P8="$P8" KEY_ID="$KEY_ID" TEAM="$TEAM" SUB="$SERVICES_ID" node -e '
const fs = require("fs"), crypto = require("crypto");
const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const head = b64({ alg: "ES256", kid: process.env.KEY_ID }), body = b64({ iss: process.env.TEAM, iat: now, exp: now + 180 * 86400,
  aud: "https://appleid.apple.com", sub: process.env.SUB });
const sig = crypto.sign("sha256", Buffer.from(head + "." + body), { key: fs.readFileSync(process.env.P8), dsaEncoding: "ieee-p1363" });
process.stdout.write(head + "." + body + "." + sig.toString("base64url"));
')
print -rn -- "$SECRET" | pbcopy

supabase secrets set --project-ref "$REF" APPLE_TEAM_ID="$TEAM" APPLE_KEY_ID="$KEY_ID" APPLE_PRIVATE_KEY="$(cat "$P8")" >/dev/null
EXPIRES=$(date -v+180d "+%-d %B %Y")
cat <<TXT

Done. The Secret Key is now on your clipboard.

In Supabase (supabase.com/dashboard › your project › Authentication › Sign In / Providers › Apple):
  Enable Sign in with Apple: on
  Client IDs:  com.ahmedwalid.orbit,$SERVICES_ID
  Secret Key (for OAuth): paste (Cmd-V)
  Save

The Secret Key works until $EXPIRES. Run this script again before then and paste the new one.
TXT
