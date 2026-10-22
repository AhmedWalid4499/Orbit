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
- **⌘K** opens search and **⌘1–6** switch tabs.
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

Money has an **Overview** and a **Calendar**. The Calendar shows what you spent each day, plus bills and recurring payments that are coming due. The **Money coach** card gives savings tips based on your real spending, and **Discuss with Claude** opens a conversation about it.

## Sync and backup

Sign in under **Settings › Account** to back up Orbit online and keep several Macs in sync. Data is stored in Supabase (Postgres), where each person can only access their own rows. The database setup is in `supabase/schema.sql`. You can sign in with Google or with email. Use the same Google account everywhere and you're in the same Orbit account.

Turn on **Sync API keys and connections** to bring your Anthropic key, GitHub token and Google sign-ins to your other devices. They're encrypted on the device with your sync passphrase (PBKDF2-SHA256 and AES-256-GCM, see `VaultCrypto.swift`), so the server only stores ciphertext. Apple connections stay on each Mac.

## Reading

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

- `Sources/Orbit/Models`: SwiftData models (tasks, events, habits, transactions, notes)
- `Sources/Orbit/Design`: theme (colors, type, pills, cards)
- `Sources/Orbit/Services`: Claude, Gmail, GitHub, reading sources, Apple Calendar/Reminders, quick capture, updater
- `Sources/Orbit/Views`: one file per screen

Debug screenshots: `ORBIT_SNAPSHOT_DIR=/some/dir build/Orbit.app/Contents/MacOS/Orbit` renders every tab in light and dark mode to PNG and then quits. Add `ORBIT_SNAPSHOT_DEMO=1` to render in-memory demo data instead of your real data. Snapshot mode makes no network calls.
