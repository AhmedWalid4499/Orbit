# Getting Joshu verified by Google

Until Google verifies Joshu, people who connect Gmail, Google Calendar or YouTube see "Google hasn't verified this app",
and only the 100 test users you list can connect at all. Verification removes both.

Joshu asks Google for:

| Permission | Used for | Google's level |
|---|---|---|
| `gmail.readonly` | Email summaries on Today, receipts, reading emails in Joshu | **Restricted** |
| `gmail.send` | Sending replies you write or approve in Joshu | **Restricted** |
| `calendar.readonly` | Google Calendar events next to your tasks | Sensitive |
| `youtube.readonly` | Your channel's stats on the YouTube tab | Sensitive |
| `email` | Knowing which account you connected | Basic |

Sensitive permissions need Google's normal review (days to a few weeks). Restricted ones (Gmail) also need a yearly paid
security assessment, called CASA, done by an independent lab. Plan for several weeks for Gmail.

All of this happens in **one Google Cloud project**: the one whose OAuth client Joshu uses (Google Cloud Console, top bar,
pick the project that has the "Desktop app" client you set up for Orbit/Joshu).

---

## Step 1. Your website on a domain you own (30 minutes)

Google checks that Joshu's homepage and privacy policy are on a domain you own.

- **Today:** the site is `ahmedwalid4499.github.io`. A Search Console verification file is already on it
  (`root-site/googlebf6ab471145cf74b.html`), so Google may already accept that you own it.
- **Better:** buy a short domain (for example `joshu.app` or `getjoshu.com`, about $10–20 a year) and point GitHub Pages to
  it. Google reviews go faster with a real domain, and it matches your "no GitHub on the website" rule. Tell me the domain
  and I'll set up the site for it.

Then:
1. Open https://search.google.com/search-console with the **same Google account that owns the Cloud project**.
2. Add the domain (Domain property, verified with a DNS record at your domain seller), or keep the existing
   `ahmedwalid4499.github.io` property if it shows as verified.

## Step 2. Fill in the consent screen (20 minutes)

Google Cloud Console › **Google Auth Platform** (older name: APIs & Services › OAuth consent screen).

**Branding**
- App name: `Joshu`
- User support email: an address you read (also put it in the privacy policy; I can add it)
- App logo: `Brand/joshu-logo-120.png` (exactly 120 × 120, matches the app)
- App home page: your homepage (e.g. `https://ahmedwalid4499.github.io/` or your new domain)
- Privacy policy: `https://ahmedwalid4499.github.io/Orbit/privacy/` (or the same page on your new domain)
- Terms of service: `https://ahmedwalid4499.github.io/Orbit/terms/`
- Authorized domains: the domain of those links (`ahmedwalid4499.github.io` or your new domain)
- Developer contact: your email

**Audience**
- User type: External
- Publishing status: click **Publish app** to move from *Testing* to *In production*.
  (This doesn't make Joshu public by itself; it lets you submit for verification. Until verified, users see the
  "unverified app" screen.)

**Data access (the permissions)**
- Add exactly these, and nothing else: `gmail.readonly`, `gmail.send`, `calendar.readonly`, `youtube.readonly`.
- For each one, paste the matching explanation from Step 3.

## Step 3. Explanations to paste (copy as they are)

- **gmail.readonly:** "Joshu is a personal organizer. When the user connects Gmail, Joshu reads their recent emails to show
  a short summary on their Today screen (what needs a reply, what's important), to find receipts and bills so they're
  added to the user's budget, and to let the user read their emails inside Joshu. Emails are shown only to that user.
  If the user turns on the AI assistant, the text of the emails being summarised is sent to Anthropic's Claude to write
  the summary, as the app explains and asks permission for. Joshu doesn't use the data for ads and doesn't sell or share it."
- **gmail.send:** "Users can reply to an email from inside Joshu. Joshu sends only the reply the user wrote or approved,
  in the same thread, when the user taps Send. Joshu never sends email on its own."
- **calendar.readonly:** "Joshu shows the user's Google Calendar events next to their tasks and plans on the Today and
  Calendar screens. It only reads events; it never changes the calendar."
- **youtube.readonly:** "Joshu's YouTube tab shows the user's own channel statistics (subscribers, views, latest videos)
  and how they change over time. It only reads the user's own channel data."

## Step 4. Privacy policy wording (I can do this part)

The policy must say, in plain words: what Google data Joshu reads, what it's used for, where it goes (your device, your
Joshu account, and Anthropic when the AI is on), how long it's kept, how to delete it, and this sentence, which is already
there: "Joshu's use and transfer of information received from Google APIs adheres to the Google API Services User Data
Policy, including the Limited Use requirements." It also needs a contact email. Tell me which email to show and I'll update it.

## Step 5. Record the demo video (15 minutes)

Upload it to YouTube as **Unlisted** and paste the link in the verification form. Use the iPhone (screen recording) or the
Mac (Cmd-Shift-5). In English:

1. Show Joshu's name and the screen where you connect Google (Settings › Connections › Add Gmail account).
2. Tap it. On Google's sign-in page, **show the browser's address bar** so the `client_id=…` in the URL is visible
   (on iPhone, tap the address bar or the "aA" menu to show the full URL).
3. Show Google's consent screen listing the permissions, then Allow.
4. Show each permission in use:
   - gmail.readonly: the Inbox summary on Today, then open an email inside Joshu.
   - gmail.send: write a reply in Joshu and tap Send; show it arrived in Gmail.
   - calendar.readonly: Google Calendar events on the Today or Calendar screen.
   - youtube.readonly: connect YouTube and show the YouTube tab.
5. Show where the user can disconnect (Settings › Connections › Disconnect).

## Step 6. Submit

Google Auth Platform › **Verification Center** › **Prepare for verification** › fill in the form (paste the explanations
and the video link) › Submit. Google replies by email, usually asking for small changes (a sentence in the privacy
policy, a clearer moment in the video). Reply in the same thread.

- **Brand and sensitive permissions** (Calendar, YouTube): usually approved in a few days to a few weeks.
- **Restricted permissions** (Gmail): after Google's review, they email you about the **CASA security assessment**. You
  pick an approved lab from their list (for example TAC Security or Leviathan), pay them, and complete their assessment
  of Joshu and its server (for an app like Joshu, usually Tier 2: an automated scan plus a questionnaire). It's renewed
  every year.

## Faster option: split it

Make a **second Google Cloud project** just for Calendar and YouTube. Verify that one first: no security assessment,
so it can be live in days. Keep Gmail in the first project in Testing (up to 100 test users) until you decide the
assessment is worth it. The app then uses one sign-in client for Calendar/YouTube and another for Gmail. Ask me and I'll
wire that up.

## Until then (TestFlight)

Google Auth Platform › Audience › **Test users** › add each tester's Google address (up to 100), including the account
you give App Review.
