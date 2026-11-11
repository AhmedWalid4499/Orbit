# Getting Joshu verified by Google, click by click

Until Google verifies Joshu, people who connect Gmail, Google Calendar or YouTube see "Google hasn't verified this app",
and only the up-to-100 test users you list can connect at all. Verification removes both.

Joshu asks Google for these permissions ("scopes"):

| Scope (paste exactly) | Used for | Google's level |
|---|---|---|
| `https://www.googleapis.com/auth/gmail.readonly` | Email summaries on Today, receipts, reading emails in Joshu | Restricted |
| `https://www.googleapis.com/auth/gmail.send` | Sending replies you write or approve in Joshu | Restricted |
| `https://www.googleapis.com/auth/calendar.readonly` | Google Calendar events next to your tasks | Sensitive |
| `https://www.googleapis.com/auth/youtube.readonly` | Your channel's stats on the YouTube tab | Sensitive |
| `email` (shows as `.../auth/userinfo.email`) | Knowing which account you connected | Basic |

Sensitive = Google's normal review (days to a few weeks). Restricted (Gmail) = that review **plus** a yearly paid security
assessment (CASA) by an independent lab. Budget several weeks for Gmail.

Use **one Google account for everything below**: the one that owns Joshu's Google Cloud project (the one you used when you
set up "Add Gmail account").

---

## Step 0. Open the right Google Cloud project (2 minutes)

1. Go to **https://console.cloud.google.com** and sign in.
2. At the top left, next to "Google Cloud", click the **project name** (a drop-down). A window opens listing your projects.
3. Pick the project you made for Orbit/Joshu. Not sure which? Pick one, then go to
   **https://console.cloud.google.com/auth/clients**: the right project lists an OAuth client of type **Desktop**
   (the one Joshu uses). If it's not there, switch project and check again.
4. Keep this project selected for every step below (the project name stays at the top left).

The pages you'll use all live under **☰ menu (top left) › Google Auth Platform**, with a left sidebar:
**Overview · Branding · Audience · Clients · Data Access · Verification Center**.
(In older layouts it's **☰ › APIs & Services › OAuth consent screen**, which opens the same pages.)

---

## Step 1. A website domain you own (30–60 minutes)

Google only accepts a homepage and privacy policy on a domain you prove is yours.

### Option A, recommended: your own domain
1. Buy a domain at a registrar (Namecheap, Cloudflare, Porkbun, GoDaddy…), for example `joshu.app` or `getjoshu.com`.
2. Tell me the domain. I'll point the Joshu website to it (GitHub Pages) and give you the exact DNS records to add.
3. Add those records at your registrar. In Namecheap: **Domain List › Manage** next to the domain **› Advanced DNS ›
   Add New Record**. In Cloudflare: select the domain **› DNS › Records › Add record**.

### Option B: keep `ahmedwalid4499.github.io`
It may work (a Google verification file is already on it), but reviews are slower and it shows "github" in Joshu's links.

### Prove you own it in Search Console
1. Go to **https://search.google.com/search-console** (same Google account).
2. Top left, click the **property drop-down › + Add property**.
3. Choose:
   - **Domain** (Option A): type `joshu.app` (your domain) › Continue. Google shows a **TXT record** starting with
     `google-site-verification=`. Copy it.
     At your registrar, add a record: Type **TXT**, Host **@**, Value **(paste)**, TTL automatic › Save.
     Back in Search Console, click **Verify** (if it fails, wait 10–30 minutes and click Verify again).
   - **URL prefix** (Option B): type `https://ahmedwalid4499.github.io/` › Continue › **HTML file** method. If it says
     "Ownership auto verified", you're done. Otherwise tell me and I'll upload the file it gives you.
4. When it says **Ownership verified**, you're done here.

---

## Step 2. Branding page (15 minutes)

**☰ › Google Auth Platform › Branding** (or go to **https://console.cloud.google.com/auth/branding**).

Fill in, then click **Save** at the bottom:

| Field | What to put |
|---|---|
| App name | `Joshu` |
| User support email | Pick your address from the list (it must be your account or a group you own) |
| App logo | Upload `Brand/joshu-logo-120.png` from the project folder (120 × 120, same as the app icon) |
| Application home page | Your homepage, e.g. `https://joshu.app/` (or `https://ahmedwalid4499.github.io/`) |
| Application privacy policy link | `https://joshu.app/privacy/` (or `https://ahmedwalid4499.github.io/Orbit/privacy/`) |
| Application terms of service link | `https://joshu.app/terms/` (or `https://ahmedwalid4499.github.io/Orbit/terms/`) |
| Authorized domains | Click **+ Add domain** › `joshu.app` (or `ahmedwalid4499.github.io`) |
| Developer contact information | Your email |

Note: changing the logo or name later re-triggers brand review, so set them once.

---

## Step 3. Data Access page: add the scopes and explain them (20 minutes)

**☰ › Google Auth Platform › Data Access** (or **https://console.cloud.google.com/auth/scopes**).

1. Click **Add or remove scopes**. A panel opens on the right.
2. Scroll to the bottom of the panel, to **Manually add scopes**. Paste these four lines into the box:
   ```
   https://www.googleapis.com/auth/gmail.readonly
   https://www.googleapis.com/auth/gmail.send
   https://www.googleapis.com/auth/calendar.readonly
   https://www.googleapis.com/auth/youtube.readonly
   ```
3. Click **Add to table**, check that all four are ticked (plus `.../auth/userinfo.email`), then **Update**.
4. Back on the page, they appear under **Your sensitive scopes** and **Your restricted scopes**. Each section has a box
   **"How will the scopes be used?"** Paste the matching text below.
5. There is also a box for a **demo video** link: leave it until Step 5, then come back and paste it.
6. Click **Save**.

Text for **restricted scopes** (Gmail):
> Joshu is a personal organizer. When the user connects Gmail, Joshu reads their recent emails to show a short summary
> on their Today screen (what needs a reply, what's important), to find receipts and bills so they're added to the user's
> budget, and to let the user read their emails inside Joshu (gmail.readonly). Users can also reply to an email from inside
> Joshu: Joshu sends only the reply the user wrote or approved, in the same thread, when the user taps Send, and never
> sends email on its own (gmail.send). Email content is shown only to that user. If the user turns on the AI assistant,
> the text of the emails being summarised is sent to Anthropic's Claude to write the summary, which the app explains and
> asks permission for first. Joshu doesn't use this data for advertising and doesn't sell or share it.

Text for **sensitive scopes** (Calendar, YouTube):
> calendar.readonly: Joshu shows the user's Google Calendar events next to their tasks and plans on the Today and
> Calendar screens. It only reads events and never changes the calendar.
> youtube.readonly: Joshu's YouTube tab shows the user's own channel statistics (subscribers, views, latest videos) and
> how they change over time. It only reads the user's own channel data.

---

## Step 4. Privacy policy wording (I do this; you pick the email)

Tell me which email to show as Joshu's contact. I'll update the privacy page so it says plainly what Google data Joshu
reads, what for, where it goes (your device, your Joshu account, and Anthropic when the AI is on), how long it's kept and
how to delete it. The required "Limited Use" sentence is already there.

---

## Step 5. Record the demo video (15–20 minutes)

Google wants to see: the sign-in screen with Joshu's **client ID visible in the address bar**, the consent screen, and
each scope being used. Record on the **Mac** (the address bar is easier to show there).

1. Start recording: press **⌘ Shift 5 › Record Entire Screen › Record**. (Stop with the ■ button in the menu bar.)
2. Open Joshu › **Settings › Connections › Add Gmail account…**
3. On Google's page, **click the browser's address bar** so the full link is visible; slowly scroll through it so
   `client_id=...apps.googleusercontent.com` can be read. If the sign-in opens in a small window without an address bar,
   tell me: I'll add an option to open it in Safari for the recording.
4. Pick your account. On the consent screen, **pause** so all the permissions can be read, then **Allow**.
5. Show each permission working:
   - **gmail.readonly:** Today › Inbox card (the summary), then tap an email to read it inside Joshu.
   - **gmail.send:** in that email, type a short reply › **Send**; then switch to Gmail in the browser and show it arrived.
   - **calendar.readonly:** Today › Agenda, or the Calendar tab, showing Google Calendar events.
   - **youtube.readonly:** Settings › Connections › YouTube › Connect, then the **YouTube** tab with your channel stats.
6. Show how to disconnect: **Settings › Connections › Disconnect**.
7. Stop recording. The video saves to your Desktop.
8. Upload: **https://studio.youtube.com › Create (top right) › Upload videos ›** pick the file › Visibility
   **Unlisted** › Save. Copy the link.
9. Go back to **Data Access** (Step 3) and paste the link in the demo video box › **Save**.

---

## Step 6. Publish and submit (10 minutes)

1. **☰ › Google Auth Platform › Audience** (or **https://console.cloud.google.com/auth/audience**).
   Under **Publishing status: Testing**, click **Publish app › Confirm**. It becomes **In production**.
   (Users still see the "unverified" screen until Google approves; this just lets you submit.)
2. **☰ › Google Auth Platform › Verification Center** (or **https://console.cloud.google.com/auth/verification**).
   It lists what's needed (branding, scopes, video). When everything is green, click **Prepare for verification**
   (or **Submit for verification**), confirm the details and **Submit**.
3. Watch your email (the developer contact address). Google's Trust & Safety team writes from an `@google.com` address,
   often asking for small changes. **Reply in the same email thread.** Send me their message and I'll prepare the answer
   or the fix.

What happens next:
- **Branding + Calendar + YouTube:** usually approved in a few days to a few weeks.
- **Gmail:** after their review, they email you about the **CASA security assessment**. They link a list of approved
  labs (for example TAC Security, Leviathan). You pick one, pay them, and complete their assessment of Joshu and its
  server. For an app like Joshu it's usually **Tier 2** (an automated scan plus a questionnaire). It's renewed every year.
  I can help fill in the technical questionnaire.

---

## Faster option: verify Calendar and YouTube first

Make a second Google Cloud project only for Calendar and YouTube (no Gmail). It needs no security assessment, so it can be
approved in days. Gmail stays in the first project, in Testing, until you decide the assessment is worth it. Ask me and
I'll set up the second sign-in in the app.

---

## Until verified: test users (for TestFlight)

**☰ › Google Auth Platform › Audience › Test users › + Add users** › type each tester's Google address (one per line,
up to 100) › **Save**. Include the Google account you give App Review.
Test users can connect while the app is in **Testing**. Once you click **Publish app**, unverified sign-ins show a warning
("Google hasn't verified this app" › Advanced › Go to Joshu) and Gmail is limited to 100 users in total until Google
approves.
