# Turning on Sign in with Apple (about 15 minutes)

Joshu now signs in with Apple only: Apple's own sheet on iPhone, Apple's sign-in page on the Mac. Until the steps below
are done, the app keeps showing the old email and Google sign-in, so nothing breaks in the meantime. As soon as the
server has Apple switched on, the app shows "Sign in with Apple" by itself.

Accounts made earlier with email or Google keep working: under the Apple button there's a small
"Made your account with email or Google before?" link.

You need: your Apple Developer account (developer.apple.com) and the Supabase dashboard (supabase.com/dashboard).

---

## 1. Turn on Sign in with Apple for the iPhone app (2 minutes)

1. Go to **https://developer.apple.com/account/resources/identifiers/list**.
2. In the list, click **com.ahmedwalid.orbit** (the iPhone app). If it's not in the list, it's created automatically
   the next time the app is installed; do step 1 after that.
3. Under **Capabilities**, scroll to **Sign In with Apple**, tick it. If a **Configure** button appears next to it,
   leave it as **Enable as a primary App ID**.
4. Click **Save** (top right) › **Confirm**.

## 2. Make a "Services ID" for the Mac's web sign-in (5 minutes)

1. Same page, click the blue **+** next to "Identifiers".
2. Choose **Services IDs** › **Continue**.
3. Description: `Joshu sign-in` · Identifier: `com.ahmedwalid.orbit.signin` › **Continue** › **Register**.
4. In the list, open the drop-down at the top right of the list (it says "App IDs") and pick **Services IDs**. Click
   **com.ahmedwalid.orbit.signin**.
5. Tick **Sign In with Apple** › click **Configure** next to it:
   - **Primary App ID:** `com.ahmedwalid.orbit`
   - **Domains and Subdomains:** `qngpfkqupvxeuxzwdeex.supabase.co`
   - **Return URLs:** `https://qngpfkqupvxeuxzwdeex.supabase.co/auth/v1/callback`
   - **Next** › **Done** › **Continue** › **Save**.

## 3. Make the Sign in with Apple key (3 minutes)

1. Go to **https://developer.apple.com/account/resources/authkeys/list** › blue **+**.
2. Key Name: `Joshu Sign in with Apple`. Tick **Sign in with Apple** › **Configure** › Primary App ID
   `com.ahmedwalid.orbit` › **Save**.
3. **Continue** › **Register**.
4. Note the **Key ID** (10 characters, shown on the page) and click **Download**. You get `AuthKey_XXXXXXXXXX.p8` in
   Downloads. Apple lets you download it only once: keep it in a private folder (not in the Joshu project folder).

## 4. Run the setup script (1 minute)

In Terminal, in the Joshu project folder (replace the file name and Key ID with yours):

```
scripts/setup-apple-signin.sh ~/Downloads/AuthKey_XXXXXXXXXX.p8 XXXXXXXXXX
```

It puts the "Secret Key" for Supabase on your clipboard and saves the key on the server (used when someone deletes their
account). If it asks you to sign in to Supabase, run `npx supabase login` and run it again.

## 5. Switch Apple on in Supabase (2 minutes)

1. Go to **https://supabase.com/dashboard** › your Joshu project › **Authentication** (left sidebar) ›
   **Sign In / Providers** (older layout: **Providers**).
2. Find **Apple** in the list and open it.
3. **Enable Sign in with Apple:** on.
4. **Client IDs:** `com.ahmedwalid.orbit,com.ahmedwalid.orbit.signin`
5. **Secret Key (for OAuth):** paste (Cmd-V) what the script copied.
6. **Save**.
7. Still under **Authentication**, open **URL Configuration** › **Redirect URLs** and check
   `com.personal.orbit://auth-callback` is in the list (it is if Google sign-in worked before). If not, **Add URL**.

## 6. Try it

- iPhone: open Joshu › Settings › Account › Sign out (if you want to test) › **Sign in with Apple**.
- Mac: Settings › Account › **Sign in with Apple** opens Apple's page; sign in and it comes back to Joshu.

**Keep your existing account:** if you sign in with Apple and choose **Share My Email** with the same address as your
current Joshu account, Supabase links them to the same account. If you choose **Hide My Email**, Apple gives a private
address and it becomes a new, empty account. For your own account, sign in with the email link instead, or share your
real email.

**Every 6 months:** Apple's Secret Key expires (the script prints the date). Run step 4 again and paste the new one in
step 5. Only the Mac's sign-in needs it; iPhone sign-in keeps working regardless.
