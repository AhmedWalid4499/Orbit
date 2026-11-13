# Turning on "Sign in with Microsoft" (Outlook / Hotmail), about 10 minutes

Joshu's Connect email screen has a **Sign in with Microsoft** button for Outlook, Hotmail and Live addresses. It stays
hidden until Joshu has its own Microsoft registration. Microsoft charges nothing for this and doesn't review the app.

## 1. Register Joshu with Microsoft

1. Go to **https://entra.microsoft.com** and sign in with your Microsoft account.
   - If it says you need a directory or an Azure account, make the free one it offers. It may ask for a card to check
     you're a person; registering an app is free.
2. Left sidebar: **Applications** › **App registrations** › **+ New registration**.
3. Fill in:
   - **Name:** `Joshu`
   - **Supported account types:** *Accounts in any organizational directory and personal Microsoft accounts*
   - **Redirect URI:** choose **Public client/native (mobile & desktop)** and type `http://127.0.0.1`
4. Click **Register**.

## 2. Two settings

1. On the app's page, open **Authentication** (left). Under **Advanced settings**, set
   **Allow public client flows** to **Yes**. Click **Save**.
2. Open **API permissions** › **+ Add a permission** › **Microsoft Graph** › **Delegated permissions**. Tick
   `offline_access`, `openid`, `email`, `profile` and, under **IMAP**, `IMAP.AccessAsUser.All`. Click **Add permissions**.

## 3. Send me the ID

Back on **Overview**, copy the **Application (client) ID** (it looks like `1a2b3c4d-…`) and send it to me. It isn't a
secret: it only identifies Joshu. I put it in `Sources/Orbit/Services/MicrosoftMail.swift` and release an update, and
the button appears.
