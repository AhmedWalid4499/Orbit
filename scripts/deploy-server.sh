#!/bin/zsh
# Deploys Joshu's server functions (the AI for Pro users, and App Store subscription checks) to the Supabase
# project in Support/Supabase.json. Needs the Supabase CLI (brew install supabase/tap/supabase) and `supabase login`.
# The Anthropic key is set by you, once, as a server secret; it never goes in the app or the repo:
#   supabase secrets set --project-ref <ref> ANTHROPIC_API_KEY=sk-ant-…
set -e
cd "$(dirname "$0")/.."
command -v supabase >/dev/null || { echo "Install the Supabase CLI first: brew install supabase/tap/supabase"; exit 1; }
REF=$(python3 -c "import json,re;print(re.search(r'https://([a-z0-9]+)\.supabase', json.load(open('Support/Supabase.json'))['url']).group(1))")
supabase functions deploy claude --project-ref "$REF"
# Apple's server notifications carry no Joshu sign-in, so this one checks Apple's signature itself instead.
supabase functions deploy subscription --project-ref "$REF" --no-verify-jwt
echo "Deployed. App Store Server Notifications URL: https://$REF.supabase.co/functions/v1/subscription"
