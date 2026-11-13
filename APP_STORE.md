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
   URL Configuration › Redirect URLs so sign-in can come back to it.

## 3. App Store Connect
1. **Create the app.** Use bundle ID `com.ahmedwalid.orbit` (iPhone; keep it, it's invisible to users).
   Name it **Joshu**. If the name is taken, try "Joshu: Life Organizer".
2. **Subscriptions (Joshu Pro).** The app, the paywall (plans, Restore, Terms and Privacy links, renewal small print)
   and the server that checks Apple's receipts are done; only these App Store Connect steps are left.
   1. **Business › Agreements:** accept the **Paid Apps** agreement, then fill in **Bank** and **Tax**. Until this is
      active, the App Store returns no products and the paywall says "The App Store isn't answering".
   2. **Apps › Joshu › Monetization › Subscriptions › Create** a subscription group. Reference name `Joshu Pro`;
      under Localization, display name `Joshu Pro`.
   3. In the group, **Create** two subscriptions. The Product IDs must match exactly (they can't be changed later):

      | Reference name | Product ID          | Duration | Price  |
      |----------------|---------------------|----------|--------|
      | Pro Monthly    | `joshu.pro.monthly` | 1 month  | $7.99  |
      | Pro Yearly     | `joshu.pro.yearly`  | 1 year   | $59.99 |

      For each one, set the price (Subscription Prices › Add, pick the US price; Apple fills in the other countries),
      a localization (display name "Joshu Pro Monthly" / "Joshu Pro Yearly", description "The assistant and everything
      it does, every month" / "…every year"), and Review Information: a screenshot of the Joshu Pro screen
      (I can render one) and the note "Unlocks the AI assistant".
   4. Optional: **Introductory offer** on the yearly plan, for example a 1-week free trial. The app shows Apple's own
      purchase sheet, which states the trial, so no app change is needed.
   5. **The first time only:** subscriptions are reviewed together with an app version. On the version page, under
      **In-App Purchases and Subscriptions**, add both before you press Submit for Review.
   6. **Users and Access › Sandbox › Test Accounts:** add a sandbox Apple ID. On your iPhone, Settings › Developer ›
      Sandbox Apple Account, sign in with it, then buy Pro in the TestFlight build: it's free and renews every few
      minutes.
3. **App Store Server Notifications (Version 2).** App Information › App Store Server Notifications: set both the
   Production and the Sandbox URL to `https://qngpfkqupvxeuxzwdeex.supabase.co/functions/v1/subscription`. This keeps
   renewals, cancellations and refunds in step on your other devices. (The function is deployed and answering.)
4. **App Privacy.** Answer exactly as `iOS/OrbitPhone/PrivacyInfo.xcprivacy` says. Data linked to you, for app
   functionality, no tracking: email address, name, user ID (account), other user content (synced data), text messages (bank texts
   you choose to log; email reading is switched off for now), other financial info (spending), health and fitness (daily
   summary), photos (receipts and card photo), purchase history. Coarse location: not linked, app functionality.
5. **URLs.**
   - Privacy: https://ahmedwalid4499.github.io/Orbit/privacy/
   - Terms (EULA): https://ahmedwalid4499.github.io/Orbit/terms/
   - Support: the site's home page.
6. **Assets.** Screenshots (I can render them), a description, keywords and an age rating (4+).
   Before submitting: create a key with Sign in with Apple enabled (Apple Developer › Keys), then set
   `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the .p8 file's contents) as Supabase secrets.
   Deleting an account uses them to end Sign in with Apple, as Apple requires.
7. **Review notes.** Say that Joshu Pro needs a free account, because the assistant runs on the account across devices. Give a demo Joshu account with Pro (grant it with the same SQL as yours), so the reviewer can try the AI assistant.

## 4. Sign in with Apple only (Nov 2026)
Joshu signs in with Apple only and has no Google connections (Gmail, Google Calendar, YouTube and LinkedIn are switched
off by `GoogleServices.enabled` in `Services/Gmail.swift`), so no Google app verification is needed.
Turn Apple on for the account server once: follow `SIGN_IN_WITH_APPLE.md` (Services ID, key,
`scripts/setup-apple-signin.sh`, Supabase › Authentication › Apple). Until then the app still shows email and Google
sign-in. The Secret Key for the Mac's web sign-in expires every 6 months; rerun the script before then.
App Review signs in with their own Apple ID; Pro is bought in the sandbox, so no demo account is needed for sign-in.

## 4b. Apple Wallet pass for the card
Run `scripts/setup-wallet-pass.sh` once in Terminal: it makes a certificate request, you create a Pass Type ID
(`pass.com.ahmedwalid.orbit.card`) and its certificate on developer.apple.com, and it stores the certificate as Supabase
secrets and deploys `supabase/functions/wallet-pass`. "Add to Apple Wallet" appears on the card only once that's done.

## The App Store build leaves out
`AppStoreBuild.isOn` (set by `gen-ios-project.py --app-store`): your own Anthropic key no longer unlocks Pro features
(it still powers the AI), the OpenAI voice key and Goodreads website updates (read-only import stays). Everyday installs keep all of them.

## 5. Things App Review may push back on
- **Goodreads updates** work by driving Goodreads' website with your sign-in (Goodreads has no API). Keep it, but
  expect it may need to come out if Goodreads or Apple object.
- **Health** needs a clear reason in the review notes (habits are ticked from workouts and steps; read-only).
- **Bank texts and Apple Pay** go through Shortcuts automations that the user sets up; that's allowed.

## 6. The Mac app
The Mac App Store requires sandboxing, which would switch off Kindle and Apple Books import, reading your Chrome tab
and the built-in updater. Recommended instead:
- Keep the Mac app as a download from the website, now **notarized** with the paid account (no more
  "Open Anyway" warning).
- Pro bought on iPhone unlocks the Mac automatically through your Joshu account (the server keeps one Pro status per
  account).
