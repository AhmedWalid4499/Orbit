#!/bin/zsh
# One-time setup so Joshu can make Apple Wallet passes of your card. Two steps:
#
#   scripts/setup-wallet-pass.sh
#       Makes a private key (kept in your login Keychain, never in a file) and a certificate request on your Desktop.
#       Then on developer.apple.com: Identifiers › + › Pass Type IDs › pass.com.ahmedwalid.orbit.card, and
#       Certificates › + › Pass Type ID Certificate › that ID › upload Joshu-pass.certSigningRequest › download the .cer.
#
#   scripts/setup-wallet-pass.sh /path/to/downloaded.cer
#       Stores the certificate and key as Supabase server secrets (never in the app or the repo), deploys the
#       wallet-pass function and removes the key from the Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v supabase >/dev/null; then supabase() { command supabase "$@"; }; else supabase() { npx --yes supabase@2 "$@"; }; fi
REF=$(python3 -c "import json,re;print(re.search(r'https://([a-z0-9]+)\.supabase', json.load(open('Support/Supabase.json'))['url']).group(1))")
TEAM="${ORBIT_TEAM_ID:-Y2K55S3UA9}"
TYPE_ID="${WALLET_PASS_TYPE_ID:-pass.com.ahmedwalid.orbit.card}"
SERVICE="Joshu Wallet pass key"
CSR="$HOME/Desktop/Joshu-pass.certSigningRequest"

WORK=$(mktemp -d); chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

if [[ $# -eq 0 ]]; then
  openssl req -new -newkey rsa:2048 -nodes -keyout "$WORK/pass.key" -out "$CSR" -subj "/CN=Joshu Wallet Pass/O=Joshu" 2>/dev/null
  security add-generic-password -U -a joshu -s "$SERVICE" -w "$(cat "$WORK/pass.key")"
  cat <<TXT
Made the certificate request: $CSR
(The matching private key is in your login Keychain as "$SERVICE".)

On developer.apple.com:
  1. Identifiers › + › Pass Type IDs: Description "Joshu card", Identifier $TYPE_ID (skip if it exists).
  2. Certificates › + › Pass Type ID Certificate › pick $TYPE_ID › upload Joshu-pass.certSigningRequest › Download.
Then run:  scripts/setup-wallet-pass.sh <the downloaded .cer>
TXT
  exit 0
fi

CER="$1"
[[ -f "$CER" ]] || { echo "Can't find the certificate at: $CER"; exit 1; }
KEY=$(security find-generic-password -a joshu -s "$SERVICE" -w 2>/dev/null) || { echo "No key in the Keychain. Run scripts/setup-wallet-pass.sh (no arguments) first."; exit 1; }
# The Keychain tool hands back multi-line secrets as hex.
if [[ "$KEY" == *BEGIN* ]]; then print -r -- "$KEY" > "$WORK/pass.key"; else print -rn -- "$KEY" | xxd -r -p > "$WORK/pass.key"; fi
openssl x509 -inform der -in "$CER" -out "$WORK/pass.pem" 2>/dev/null || openssl x509 -in "$CER" -out "$WORK/pass.pem"
# The certificate must belong to this key (made from the request above) and to the Pass Type ID.
[[ "$(openssl x509 -in "$WORK/pass.pem" -noout -modulus)" == "$(openssl rsa -in "$WORK/pass.key" -noout -modulus 2>/dev/null)" ]] || {
  echo "This certificate was made from a different request. Upload $CSR on developer.apple.com and download a new one."; exit 1; }
openssl x509 -in "$WORK/pass.pem" -noout -subject | grep -q "$TYPE_ID" || echo "Note: the certificate isn't for $TYPE_ID; check you picked the right Pass Type ID."

supabase secrets set --project-ref "$REF" PASS_TYPE_ID="$TYPE_ID" PASS_TEAM_ID="$TEAM" \
  PASS_CERT="$(cat "$WORK/pass.pem")" PASS_KEY="$(cat "$WORK/pass.key")" >/dev/null
supabase functions deploy wallet-pass --project-ref "$REF"
security delete-generic-password -a joshu -s "$SERVICE" >/dev/null 2>&1 || true
rm -f "$CSR"
echo "Done. In Joshu, close and reopen the app, then My Card › Add to Apple Wallet."
