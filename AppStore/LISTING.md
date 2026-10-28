# Joshu on the App Store: what to paste where

Everything below goes into App Store Connect › your app. Lengths are within Apple's limits.

## App Information
- **Name** (30): `Joshu` (if taken: `Joshu: Life Organizer`)
- **Subtitle** (30): `Your day, money & AI assistant`
- **Category:** Productivity. **Secondary:** Lifestyle
- **Privacy Policy URL:** https://ahmedwalid4499.github.io/Orbit/privacy/
- **Terms of Use (EULA)**, in the description's last line or App Information › License Agreement: https://ahmedwalid4499.github.io/Orbit/terms/

## Version page
- **Screenshots (iPhone 6.9-inch):** the nine images in `AppStore/iPhone 6.9-inch/`, in their numbered order.
- **Promotional text** (170, can be changed any time without review):
  > Your whole life in one calm place: tasks, calendar, habits, money and books, with an AI assistant you name yourself that plans your day and gets things done.
- **Keywords** (100): `planner,todo,tasks,habits,budget,expense,calendar,journal,reading,goodreads,routine,goals,focus`
- **Support URL:** https://ahmedwalid4499.github.io/Orbit/
- **Marketing URL:** https://ahmedwalid4499.github.io/Orbit/pricing/
- **Copyright:** `2026 Ahmed Walid`

**Description** (4000):

> Joshu brings your whole life into one calm place: your day, tasks, calendar, habits, money, reading, ideas and dreams, on your iPhone and Mac, always in sync.
>
> YOUR DAY, AT A GLANCE
> • Today shows what's due, what's next, your habits, money left to spend and the weather
> • Plan tomorrow in a minute each evening, with your top 3
> • A gentle check-in each day that turns into your journal
>
> TASKS, CALENDAR AND REMINDERS
> • Apple, Google and Outlook calendars side by side
> • Tasks with reminders, including "remind me when I get home"
> • Widgets, Siri and Shortcuts for quick adds
>
> MONEY THAT LOGS ITSELF
> • Card payments from your bank's texts and Apple Pay land in Money by themselves, through Shortcuts automations you set up once
> • Budgets, bills and subscriptions, with a heads-up before rent or a price rise
> • Snap a paper receipt and it's filed
>
> READING, IDEAS AND DREAMS
> • A bookshelf with your Goodreads, Kindle and Apple Books, reading time and a yearly goal
> • Ideas: projects for your writing, where every idea can grow
> • A bucket list with trips, bookings found in your email, and places to go
>
> JOSHU PRO: YOUR OWN AI ASSISTANT
> Name your assistant anything you like. Talk or type, or just say "Hey" and its name while Joshu is open.
> • It plans with you, writes, searches the web, reads documents and helps with code
> • It adds tasks, events, expenses, notes and books for you
> • A morning brief and a summary of your day
> • Email summaries: what needs a reply, and what can wait
> • A money coach with tips on where your money goes
> • LinkedIn job alerts, laid out job by job
> • As many email accounts as you like
>
> Joshu is free. Joshu Pro is $7.99 a month or $59.99 a year, and works on every device you sign in to.
> The assistant only sends what each request needs to the AI, after you allow it, and it isn't used to train AI models.
>
> Payment is charged to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the end of the period; manage or cancel it in your App Store account settings.
> Terms of Use: https://ahmedwalid4499.github.io/Orbit/terms/
> Privacy: https://ahmedwalid4499.github.io/Orbit/privacy/

- **What's New** (first version): `Welcome to Joshu.`

## Subscriptions (group "Joshu Pro")
| | Product ID | Display name | Description (45) |
|---|---|---|---|
| Monthly | `joshu.pro.monthly` | Joshu Pro Monthly | Your AI assistant and every smart feature |
| Yearly | `joshu.pro.yearly` | Joshu Pro Yearly | Your AI assistant and every smart feature |

- **Review screenshot** for both: `AppStore/Subscription review/joshu-pro-paywall.png`
- **Review notes** for both: `Opens from Settings › Account › See Pro, or any "Get Pro" button. Unlocks the AI assistant and the AI features listed on the screen.`
- Group display name: `Joshu Pro`

## App Review Information
- **Sign-in required:** yes. Create a test account in Joshu (email and password), give it Pro from the admin page, and enter it here.
- **Notes:**

> Joshu is a personal organizer. Most features work without an account; an account syncs data between the user's devices.
>
> TEST ACCOUNT: the account above has Joshu Pro, so the AI assistant works (tap the orb in the top bar, or "Joshu" in the tab bar). The first time the AI is used, Joshu asks permission to send the request to Anthropic's Claude AI.
>
> SIGN IN: email and password, Sign in with Apple, or Google.
>
> GMAIL: connecting Gmail uses Google's OAuth. Google is still verifying Joshu's Gmail access, so only test users can connect Gmail for now; everything else works without it.
>
> GOODREADS (optional, Reading › Goodreads sync): Goodreads has no public API. Joshu shows Goodreads' own sign-in page in a web view, and with the user's permission updates their reading progress and posts their reviews on goodreads.com, as the user would themselves.
>
> BANK TEXTS AND APPLE PAY (optional, Money › Auto-log card payments): the user adds our Shortcuts and creates Shortcuts automations themselves. Joshu never reads messages on its own.
>
> APPLE HEALTH (optional): read-only. Steps, sleep and workouts are shown next to habits and tick off workout habits. Joshu never writes to Health.
>
> ACCOUNT DELETION: Settings › Account › Delete Account.

## App Privacy (App Store Connect › App Privacy)
Data **linked to the user**, used only for **App Functionality**, **not** for tracking:
- Contact Info: Email Address, Name
- User Content: Other User Content (tasks, notes, ideas), Photos (the profile photo)
- Financial Info: Other Financial Info (the money entries the user adds)
- Health & Fitness: Health, Fitness (only if the user connects Apple Health)
- Purchases: Purchase History

Data **not linked** to the user: Location (coarse, to find places nearby and the weather). No data is used for tracking. This matches `iOS/OrbitPhone/PrivacyInfo.xcprivacy`.

## Age rating
Answer "None" to everything. The one "Yes" is **unrestricted web access**: the assistant can search the web and read pages. The result is usually 13+ or 17+, depending on Apple's current questions.
