# Orbit

A native macOS app for organizing your life: Today dashboard, calendar, tasks, habits, money and notes. Built with SwiftUI and SwiftData. Everything is stored locally on this Mac.

## Install

**[Download Orbit.dmg](https://github.com/AhmedWalid4499/Orbit/releases/latest/download/Orbit.dmg)**, open it, and drag Orbit into Applications.

The first time you open it, macOS may say it can't check Orbit for malware, because Orbit isn't from the App Store. Go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway**. After that, Orbit updates itself.

**Windows:** [Download Orbit-Setup.exe](https://github.com/AhmedWalid4499/Orbit/releases/latest/download/Orbit-Setup.exe) and run it. If Windows shows "Windows protected your PC", click **More info › Run anyway**; this happens once, because the app isn't code-signed. Sign in with the same Orbit account as on your Mac and your data comes with you. The Windows app updates itself too. Ask, the morning brief, the journal check-in, the money coach, Gmail inbox summaries and expenses from email work on Windows too: enter your key-sync passphrase in Settings to unlock the API key and Gmail sign-ins from your Mac, or add them on the PC.

## Build from source

```bash
./scripts/build-app.sh
open build/Orbit.app
```

To keep it, drag `build/Orbit.app` into `/Applications`.

## Updates

Orbit checks this repository's [Releases](https://github.com/AhmedWalid4499/Orbit/releases) every few hours. When a new version is out, a green **Update to x.y.z** button appears in the top bar. Click it and Orbit downloads the new version, checks it's signed by the same developer, installs it and restarts. You can also check by hand from **Orbit › Check for Updates…** or in **Settings › General**.

To publish a new version: `scripts/release.sh 1.2.0 "What changed"`.

## Using it

- **⌥Space** anywhere opens quick capture. It works out what you typed:
  - `call mom tomorrow` becomes a task due tomorrow
  - `dentist thu 3pm #health` becomes an event
  - `$12 lunch` becomes an expense and `+500 freelance` becomes income
  - `note: …` and `journal: …` go to Notes
  - `!`, `!!`, `!!!` set priority
- **⌘K** opens search and **⌘1–9** switch tabs.
- The menu bar icon shows your next event and the tasks due today.
- **Settings › Connections** links Apple Calendar and Apple Reminders. Apple Calendar includes Google, iCloud and Outlook calendars that are already added to macOS.

## Claude AI

Paste an Anthropic API key into **Settings › AI** (⌘,). The key is stored in the macOS Keychain. Turning it on adds:

- **Morning brief:** a card at the top of Today with a headline, a summary of the day, three focus items and a heads-up. It's generated once a day, and ↻ regenerates it.
- **Smart capture:** text typed into ⌥Space is sorted by Claude, and one line can hold several items ("dentist thu 3pm and buy milk"). If the API can't be reached, the offline parser handles it instead.

Both features use `claude-opus-5-5`, with server-side refusal fallback turned on. Each can be switched off in Settings › AI.

## Ask Claude

Click **Ask Claude** in the top bar, or press ⌘J, to open a chat panel. Claude can talk things through and also act in Orbit: create habits, tasks, events, notes and expenses, add recommended books to your reading list, and change your budget. Every action shows an **Undo** button.

## Money

Money has an **Overview**, a **Calendar** and **Subscriptions**. The Calendar shows what you spent each day, plus bills and recurring payments that are coming due. The **Money coach** card gives savings tips based on your real spending, and **Discuss with Claude** opens a conversation about it.

**Import statement** reads the CSV or PDF statement you download from your bank: it finds the columns (including separate debit and credit columns, Arabic headers and day-first dates), sorts lines into categories, and skips anything already in Orbit. PDFs are read by Claude, so they need your API key.

**Subscriptions** lists every recurring charge with the monthly and yearly total. Orbit finds them in your transactions and in receipt emails, flags price increases, and reminds you two days before a free trial turns into a paid plan. **Which can I cut?** asks Claude to go through them with you.

## Documents

Keep your passport, ID, driving licence, car registration, insurance, memberships and warranties in one place. Orbit reminds you before each one expires (a month by default, six months for passports and visas). Warranties are added by themselves from order emails that mention one.

## Focus

Hover over a task and click the timer, or use **Focus** on Today, to start a 15, 25 or 50-minute block. The countdown shows in the top bar and in the menu bar, a notification tells you when to take a break, and your focus time shows on Today and in the Week in review.

## Plan tomorrow

In the evening, **Plan tomorrow** on Today (or the 8:30 pm reminder) walks you through what's left today (done, move to tomorrow, or no date), shows tomorrow's calendar, and asks for your top 3. They appear at the top of Today the next morning, and the morning brief starts from them.

## Trips

Trips live at the top of the Bucket list. **Plan trip** on a travel dream starts one, with dates, a budget, bookings and a packing list (**Suggest** asks Claude what to bring for the destination and season). Flight, hotel and other booking emails are added by themselves and filed under the right trip. Orbit reminds you to pack the evening before and three hours before each flight.

## Siri and Shortcuts

Say "Hey Siri, add to Orbit", "What's on today in Orbit", "Ask Orbit" or "Log an expense in Orbit". The same actions appear in the Shortcuts app, so you can build automations with them (for example, read your day out loud when you open your laptop in the morning).

## Reminders, review and insights

Orbit sends Mac notifications for tasks due, events about to start, bills due tomorrow, habits not done by the evening, a nightly journal check-in, and a Sunday **Week in review**. The review shows what you finished, habits kept, spending and mood, and Ask suggests three focus items for next week. **Insights** charts your mood over 90 days and finds patterns, such as mood on days you work out compared with days you don't. Set times in **Settings › Notifications**.

## Voice capture

Hold **⌥Space** and talk; let go and Ask files what you said as a task, event, expense or note. If it's a question, it goes to Ask instead. A quick tap still opens typed quick capture.

## Widgets

Right-click the desktop › **Edit Widgets** and search for Orbit to add **Orbit Today** (small, medium or large), **Orbit Habits**, or **Looking forward to**, a countdown to your next bucket-list date.

## My card

Click your avatar and choose **My Card…**. Add your headline, contact details and links (LinkedIn, website, GitHub, Instagram, X and more), pick a colour, and share it as an image together with a contact file. The card's QR code adds you to someone's contacts with all your links, or can open one link instead.

Turn on **Public link** to publish the card as a web page at `ahmedwalid4499.github.io/Orbit/card/?u=yourname`. Point the QR code at **My web page** and anyone who scans it, from a slide or a CV, always sees your latest details. The page (`docs/card/index.html`) reads from the `public_cards` table, which anyone can read; set it up with `supabase/public_cards.sql`. Email and phone are only shown if you choose to.

## Sync and backup

Sign in under **Settings › Account** to back up Orbit online and keep several Macs in sync. Data is stored in Supabase (Postgres), where each person can only access their own rows. The database setup is in `supabase/schema.sql`. You can sign in with Google or with email. Use the same Google account everywhere and you're in the same Orbit account.

Turn on **Sync API keys and connections** to bring your Anthropic key, GitHub token and Google sign-ins to your other devices. They're encrypted on the device with your sync passphrase (PBKDF2-SHA256 and AES-256-GCM, see `VaultCrypto.swift`), so the server only stores ciphertext. Apple connections stay on each Mac.

## Reading

**Highlights:** import your Kindle highlights and notes from **My Clippings.txt** (Kindle e-reader) or a notebook export from the Kindle app. **Reading timer:** press **Start reading** on a book to time the session, and Orbit tracks your minutes and your reading streak.


The reading tab is where you track books: Reading, To read, Read and Didn't finish shelves, your own categories (each with a color and icon), a yearly goal, ratings, progress and notes. Use **Add book** to search Open Library. **Connect & import** brings in:

- **Goodreads:** syncs from your public profile feed, or imports Goodreads' library export (CSV). Goodreads has no public API.
- **Apple Books:** reads the Books app's library on this Mac.
- **Kindle:** reads the library of the Kindle app on this Mac. Amazon doesn't let other apps sign in to Kindle accounts.

Imports match books by title and author, so importing twice doesn't create duplicates.

## GitHub

Add your username on the GitHub tab to see public repos, open pull requests, assigned issues and recent activity. A fine-grained read-only token, stored in the Keychain, adds private repos and the contribution graph.

## Journal check-in

Today's journal entry has a chat with Claude next to it. Claude asks about your mood and your day, and **Write my entry** turns the conversation into a first-person journal entry.

## Project layout

- `Sources/Orbit/Models`: SwiftData models (tasks, events, habits, transactions, notes, books, subscriptions, documents, focus sessions, day plans, trips and bookings)
- `Sources/Orbit/Design`: theme (colors, type, pills, cards)
- `Sources/Orbit/Services`: Claude, Gmail, GitHub, reading sources, Apple Calendar/Reminders, quick capture, updater
- `Sources/Orbit/Views`: one file per screen

Debug screenshots: `ORBIT_SNAPSHOT_DIR=/some/dir build/Orbit.app/Contents/MacOS/Orbit` renders every tab in light and dark mode to PNG and then quits. Add `ORBIT_SNAPSHOT_DEMO=1` to render in-memory demo data instead of your real data. Snapshot mode makes no network calls.
