# Getting Joshu on the App Store

What's already built: the name Joshu, the new logo, Free vs Pro in the app (paywall, upsells, one email on Free),
the server that runs the AI for Pro users (`supabase/functions/claude`), App Store purchase checks
(`supabase/functions/subscription`), account deletion, and the website's pricing, Privacy and Terms pages.

What's left needs your accounts and your OK. In order:

## 1. Apple Developer Program ($99/year)
- Enrol at developer.apple.com/programs (as an individual: your name shows as the seller).
- Once approved, tell me your **Team ID** (Membership page). I'll switch signing from your free team so TestFlight and the
  App Store work, and so the iPhone app stops needing a reinstall every 7 days.

## 2. Supabase: turn on the Pro server (about 10 minutes)
1. Supabase dashboard › SQL Editor › run `supabase/pro.sql`.
   At the end of that file, uncomment the "Give yourself Pro" lines, put your Joshu sign-in email, and run them too.
2. Install the CLI and sign in: `brew install supabase/tap/supabase` then `supabase login`.
3. Add Joshu's Anthropic key as a server secret (it never goes in the app or the repo):
   `supabase secrets set --project-ref qngpfkqupvxeuxzwdeex ANTHROPIC_API_KEY=sk-ant-…`
   Optional: `AI_DAILY_LIMIT=300` (requests per person per day).
4. Run `scripts/deploy-server.sh`.
5. Admin page: run `supabase/admin.sql`, with the last line uncommented and your email in it. Then open
   https://ahmedwalid4499.github.io/Orbit/admin/ and sign in. Add that address to Supabase › Authentication ›
   URL Configuration › Redirect URLs so "Sign in with Google" can come back to it.

## 3. App Store Connect
1. **Create the app.** Use bundle ID `com.ahmedwalid.orbit` (iPhone; keep it, it's invisible to users).
   Name it **Joshu**. If the name is taken, try "Joshu: Life Organizer".
2. **Subscriptions.** Create a group "Joshu Pro" with two auto-renewable products. The IDs must match exactly:
   - `joshu.pro.monthly`: $7.99 / 1 month
   - `joshu.pro.yearly`: $59.99 / 1 year
3. **App Store Server Notifications (Version 2).** Set the URL to
   `https://qngpfkqupvxeuxzwdeex.supabase.co/functions/v1/subscription`.
4. **App Privacy.** Data linked to you: contact info (email, for the account), user content (synced data),
   identifiers (account ID), purchases. No tracking.
5. **URLs.**
   - Privacy: https://ahmedwalid4499.github.io/Orbit/privacy/
   - Terms (EULA): https://ahmedwalid4499.github.io/Orbit/terms/
   - Support: the site's home page.
6. **Assets.** Screenshots (I can render them), a description, keywords and an age rating (4+).
7. **Review notes.** Give a demo Joshu account with Pro (grant it with the same SQL as yours), so the reviewer can try the AI assistant.

## 4. Google sign-in (Gmail) for the public
Gmail reading and sending are "restricted" Google scopes. Until Google verifies Joshu, only up to 100 test users you
add can connect Gmail.
- Public launch needs Google's OAuth verification plus a yearly CASA security assessment, a paid third-party audit.
- Until then, either keep Gmail as an invite-only beta or launch without Gmail on the App Store.
- YouTube (read-only) only needs the lighter "sensitive scope" verification.

## 5. Things App Review may push back on
- **Goodreads updates** work by driving Goodreads' website with your sign-in (Goodreads has no API). Keep it, but
  expect it may need to come out if Goodreads or Apple object.
- **LinkedIn tab** reads LinkedIn's emails in your Gmail; it depends on the Google verification above.
- **Health** needs a clear reason in the review notes (habits are ticked from workouts and steps; read-only).
- **Bank texts and Apple Pay** go through Shortcuts automations that the user sets up; that's allowed.

## 6. The Mac app
The Mac App Store requires sandboxing, which would switch off Kindle and Apple Books import, reading your Chrome tab
and the built-in updater. Recommended instead:
- Keep the Mac app as a download from the website, now **notarized** with the paid account (no more
  "Open Anyway" warning).
- Pro bought on iPhone unlocks the Mac automatically through your Joshu account (the server keeps one Pro status per
  account).
