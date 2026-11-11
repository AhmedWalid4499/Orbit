#!/bin/zsh
# One-time setup so Joshu can make Apple Wallet passes of your card. Run it in Terminal; it walks you through it:
#  1. makes a private key and a certificate request (in a private temporary folder, deleted at the end),
#  2. you create a Pass Type ID and its certificate on developer.apple.com and download the .cer,
#  3. it stores the certificate and key as Supabase server secrets (never in the app or the repo) and deploys the function.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v supabase >/dev/null; then supabase() { command supabase "$@"; }; else supabase() { npx --yes supabase@2 "$@"; }; fi
REF=$(python3 -c "import json,re;print(re.search(r'https://([a-z0-9]+)\.supabase', json.load(open('Support/Supabase.json'))['url']).group(1))")
TEAM="${ORBIT_TEAM_ID:-Y2K55S3UA9}"
TYPE_ID="${1:-pass.com.ahmedwalid.orbit.card}"

WORK=$(mktemp -d); chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT
openssl req -new -newkey rsa:2048 -nodes -keyout "$WORK/pass.key" -out "$WORK/pass.csr" -subj "/CN=Joshu Wallet Pass/O=Joshu" 2>/dev/null
cp "$WORK/pass.csr" "$HOME/Desktop/Joshu-pass.certSigningRequest"

cat <<TXT

1. Create the Pass Type ID (once):
   developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › + › Pass Type IDs
   Description: Joshu card   Identifier: $TYPE_ID

2. Create its certificate:
   Certificates › + › Pass Type ID Certificate › pick "$TYPE_ID"
   Upload the request that's now on your Desktop: Joshu-pass.certSigningRequest
   Download the certificate (pass.cer).

TXT
open "https://developer.apple.com/account/resources/identifiers/add/passTypeId" || true
read "CER?Drag the downloaded pass.cer here and press Return: "
CER="${CER//\'/}"; CER="${CER%% }"
openssl x509 -inform der -in "$CER" -out "$WORK/pass.pem" 2>/dev/null || cp "$CER" "$WORK/pass.pem"
openssl x509 -in "$WORK/pass.pem" -noout -subject | grep -q "$TYPE_ID" || echo "Note: the certificate's subject doesn't mention $TYPE_ID; check you picked the right Pass Type ID."

supabase secrets set --project-ref "$REF" PASS_TYPE_ID="$TYPE_ID" PASS_TEAM_ID="$TEAM" \
  PASS_CERT="$(cat "$WORK/pass.pem")" PASS_KEY="$(cat "$WORK/pass.key")" >/dev/null
supabase functions deploy wallet-pass --project-ref "$REF"
rm -f "$HOME/Desktop/Joshu-pass.certSigningRequest"
echo "Done. In Joshu, open My Card › Add to Apple Wallet."
