import SwiftUI
import WebKit
#if os(iOS)
import MessageUI
#endif

/// One email from Apple Mail: read it (the whole text on the Mac; the start of it on iPhone), let the assistant draft a
/// reply, then reply in Mail (the Mac opens Mail's reply window with the text written; the iPhone opens Apple's composer).
struct AppleMailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AIAssistant.shared
    let item: InboxDigest.Item

    @State private var body_ = ""
    @State private var loading = true
    @State private var reply = ""
    @State private var intent = ""
    @State private var drafting = false
    @State private var error: String?
    @State private var composing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(item.subject.isEmpty ? "Email" : item.subject).font(Theme.display(22)).lineLimit(2)
                Spacer()
                if let u = AppleMail.url(item.messageID) {
                    Button { Platform.open(u) } label: { Label("Open in Mail", systemImage: "envelope.open") }.buttonStyle(SoftButtonStyle())
                }
                Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            .padding(20)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(String(item.from.prefix(1)).uppercased()).font(Theme.ui(15, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 38, height: 38).background(Circle().fill(Theme.lime))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.from).font(Theme.ui(14, weight: .semibold))
                            Text([item.fromAddress ?? "", item.account].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    Label(item.note, systemImage: "sparkles").font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(30)
                    } else {
                        Text(body_.isEmpty ? "Open it in Mail to read the whole email." : body_)
                            .font(Theme.ui(14)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        #if os(iOS)
                        if item.source == "mail" {
                        Text("iPhone apps can't read the Mail app, so this is the start of the email from your Mac's summary.")
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        }
                        #endif
                    }
                }
                .padding(20)
            }
            composer
        }
        .sheetFrame(width: 620, height: 720)
        .task { await load() }
        #if os(iOS)
        .sheet(isPresented: $composing) {
            MailComposer(to: item.fromAddress ?? "", subject: replySubject, body: reply).ignoresSafeArea()
        }
        #endif
    }

    private var replySubject: String { item.subject.lowercased().hasPrefix("re:") ? item.subject : "Re: \(item.subject)" }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ai.hasKey {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.inkSecondary)
                    TextField("What do you want to say? (e.g. yes, 8:30 works)", text: $intent).textFieldStyle(.plain).font(Theme.ui(13))
                        .onSubmit(draft)
                    Button(drafting ? "Writing…" : "Draft reply", action: draft).buttonStyle(SoftButtonStyle()).disabled(drafting || loading)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            }
            TextEditor(text: $reply)
                .font(Theme.ui(14)).scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 160)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .overlay(alignment: .topLeading) {
                    if reply.isEmpty {
                        Text("Write a reply…").font(Theme.ui(14)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            if let error { Text(error).font(Theme.ui(12)).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("You send it from Mail.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button { Task { await replyInMail() } } label: {
                    Label("Reply in Mail", systemImage: "arrowshape.turn.up.left.fill").frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle()).fixedSize()
            }
        }
        .padding(16)
        .background(Theme.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var mailtoURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = item.fromAddress ?? ""
        c.queryItems = [.init(name: "subject", value: replySubject), .init(name: "body", value: reply)]
        return c.url
    }

    private func load() async {
        defer { loading = false }
        if item.source == "imap" {
            guard let account = IMAPMail.account(item.account) else { body_ = item.snippet ?? ""; return }
            do { body_ = try await IMAPMail.body(account, messageID: item.messageID) }
            catch { body_ = item.snippet ?? ""; self.error = error.localizedDescription }
            return
        }
        #if os(macOS)
        if Snapshot.isDemo { body_ = item.snippet ?? ""; return }
        do { body_ = try await AppleMail.body(messageID: item.messageID).trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { body_ = item.snippet ?? ""; self.error = error.localizedDescription }
        #else
        body_ = item.snippet ?? ""
        #endif
    }

    private func draft() {
        guard !drafting else { return }
        drafting = true
        error = nil
        let m = MailMessage(id: item.messageID, threadID: item.messageID, account: item.account, from: "\(item.from) <\(item.fromAddress ?? "")>",
                            fromAddress: item.fromAddress ?? "", to: "", subject: item.subject, date: nil, body: body_,
                            messageIDHeader: item.messageID, references: "", unread: false)
        let notes = intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reply : intent
        Task {
            do { reply = try await MailReader.draftReply(to: m, intent: notes) } catch { self.error = error.localizedDescription }
            drafting = false
        }
    }

    private func replyInMail() async {
        error = nil
        #if os(macOS)
        if item.source == "imap" {
            // An account Joshu reads directly: a new email in your mail app, addressed and written.
            if let u = mailtoURL { Platform.open(u) }
            return
        }
        do { try await AppleMail.openReply(messageID: item.messageID, text: reply) }
        catch {
            // The email may have left the inbox: open it in Mail instead, and copy the reply to paste.
            if !reply.isEmpty { Platform.copy(reply) }
            if let u = AppleMail.url(item.messageID) { Platform.open(u) }
            self.error = "\(error.localizedDescription)\(reply.isEmpty ? "" : " Your reply is copied, so you can paste it.")"
        }
        #else
        if MFMailComposeViewController.canSendMail() {
            composing = true
        } else {
            if let u = mailtoURL { Platform.open(u) }
        }
        #endif
    }
}

#if os(iOS)
/// Apple's mail composer, filled in. You review it and tap Send.
struct MailComposer: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !to.isEmpty { vc.setToRecipients([to]) }
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { dismiss() }
    }
}
#endif

/// Settings › Connections: Apple Mail for the inbox summary.
struct AppleMailConnection: View {
    @ObservedObject private var inbox = InboxStore.shared
    @AppStorage(AppleMail.key) private var on = false
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                MailAppIcon(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Mail").font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                #if os(macOS)
                if on {
                    Button("Disconnect") { on = false; inbox.forgetAppleMail() }
                } else {
                    Button(checking ? "Asking Mail…" : "Connect") { Task { await connect() } }
                        .buttonStyle(.borderedProminent).disabled(checking)
                }
                #endif
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true) }
            #if os(macOS)
            if on { InboxWindowControls() }
            #endif
        }
    }

    private var detail: String {
        #if os(macOS)
        on ? "Your inbox summary on Today comes from Mail: every account you've added to Mail (iCloud, Gmail, Outlook…). Joshu only reads; you send replies from Mail."
           : "Sum up your inbox from the Mail app: what needs a reply and what matters. Works with every account in Mail."
        #else
        on ? "Your Mac reads Apple Mail and shares the inbox summary here. Tap an email to open it in Mail or reply."
           : "Connect Apple Mail in Joshu on your Mac: iPhone apps can't read the Mail app, so the summary comes from your Mac."
        #endif
    }

    #if os(macOS)
    private func connect() async {
        checking = true
        problem = nil
        defer { checking = false }
        if let e = await AppleMail.checkAccess() { problem = e; return }
        on = true
        await inbox.refresh()
    }
    #endif
}

/// The Mail app's icon, drawn (blue tile, white envelope).
struct MailAppIcon: View {
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x1E9BFF), Color(hex: 0x0A6CFF)], startPoint: .top, endPoint: .bottom))
            .overlay(Image(systemName: "envelope.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

/// Settings › Connections: email accounts Joshu reads itself, on iPhone and Mac: Gmail and Outlook with one-tap sign-in,
/// iCloud, Yahoo and others with an app-specific password (kept in the Keychain).
struct EmailAccountsConnection: View {
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var pro = Pro.shared
    @State private var adding = false
    @State private var accounts = IMAPMail.accounts

    private var all: [(email: String, gmail: Bool)] {
        inbox.accounts.map { ($0, true) } + accounts.map { ($0.email, false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.pink)
                    .overlay(Image(systemName: "at").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.stickerInk))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email accounts").font(.headline)
                    Text(all.isEmpty
                         ? "Sum up your inbox on Today, read emails and draft replies, right on this device. Gmail, Outlook, iCloud, Yahoo and most email."
                         : "Joshu reads these inboxes for the summary on Today. It never marks anything read.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            ForEach(all, id: \.email) { a in
                HStack {
                    Image(systemName: "envelope").foregroundStyle(.secondary)
                    Text(a.email).font(Theme.ui(13)).lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        if a.gmail { inbox.remove(a.email) } else { IMAPMail.remove(a.email) }
                        accounts = IMAPMail.accounts
                        inbox.emailAccountsChanged()
                    }
                    .font(Theme.ui(12))
                }
            }
            Button {
                if !pro.canAddEmail(existing: all.count) { AppState.current?.openPro() } else { adding = true }
            } label: { Label(all.isEmpty ? "Connect an email account" : "Add another account", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) {
            AddEmailAccountSheet { accounts = IMAPMail.accounts; inbox.reloadAccounts(); inbox.emailAccountsChanged() }
        }
    }
}

/// Connecting an email account in as few steps as each provider allows:
/// - Gmail: Sign in with Google. Outlook / Hotmail: Sign in with Microsoft.
/// - iCloud and Yahoo (no sign-in button exists): their password page opens inside Joshu; you make a password named
///   "Joshu" and tap Copy, and Joshu picks it up and connects by itself.
struct AddEmailAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inbox = InboxStore.shared
    var added: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var providerID = "icloud"
    @State private var host = ""
    @State private var port = "993"
    @State private var checking = false
    @State private var problem: String?
    @State private var pickedByHand = false
    @State private var usePassword = false
    @State private var pageOpen = false
    @State private var watchingClipboard = false

    private var provider: IMAPMail.Provider { IMAPMail.providers.first { $0.id == providerID } ?? IMAPMail.providers[0] }
    private var validEmail: Bool { email.contains("@") && email.contains(".") }
    private var signInButton: Bool {
        (providerID == "gmail" && GoogleAuth.isConfigured && !usePassword) || (providerID == "outlook" && MicrosoftMail.isConfigured)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $email)
                        .textContentType(.username)
                        #if os(iOS)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onChange(of: email) { _, new in
                            problem = nil
                            if !pickedByHand, new.contains("@") { providerID = IMAPMail.guessProvider(new); usePassword = false }
                        }
                    Picker("Provider", selection: Binding(get: { providerID }, set: { providerID = $0; pickedByHand = true; usePassword = false; problem = nil })) {
                        ForEach(IMAPMail.providers) { Text($0.name).tag($0.id) }
                    }
                }
                if signInButton {
                    signInSection
                } else if providerID == "outlook" {
                    Section {
                        Text("Outlook and Hotmail don't allow app passwords, and Microsoft sign-in isn't switched on in this copy of Joshu yet. On a Mac, add the account to Apple Mail and connect Apple Mail.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.orange)
                    }
                } else if providerID == "other" {
                    otherSection
                } else {
                    passwordSection
                }
                if let problem {
                    Section { Text(problem).font(Theme.ui(13)).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect email")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !signInButton && providerID != "outlook" {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(checking ? "Checking…" : "Connect") { Task { await connect() } }
                            .disabled(checking || !validEmail || password.isEmpty || (providerID == "other" && host.isEmpty))
                    }
                }
            }
            .sheet(isPresented: $pageOpen) {
                if let page = provider.passwordPage {
                    PasswordPageSheet(url: page, providerName: provider.name) { caught in
                        password = caught
                        pageOpen = false
                        Task { await connect() }
                    }
                }
            }
        }
        .sheetFrame(width: 520, height: 640)
    }

    // MARK: Sections

    private var signInSection: some View {
        Section {
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    Text(providerID == "gmail" ? "Sign in with Google" : "Sign in with Microsoft").font(Theme.ui(15, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(checking)
            .listRowBackground(Color.clear)
            if providerID == "gmail" {
                Button("Use an app password instead") { usePassword = true }.font(Theme.ui(13))
            }
        } footer: {
            Text(providerID == "gmail"
                 ? "Google asks you to allow Joshu to read your email and send the replies you write. You can remove access any time in your Google account."
                 : "Microsoft asks you to allow Joshu to read your email. You can remove access any time in your Microsoft account.")
        }
    }

    private var passwordSection: some View {
        Group {
            Section {
                if provider.passwordPage != nil {
                    Button {
                        problem = nil
                        if provider.inApp { pageOpen = true } else if let page = provider.passwordPage { Platform.open(page) }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Get a password from \(provider.name)").font(Theme.ui(15, weight: .semibold))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!validEmail || checking)
                    .listRowBackground(Color.clear)
                }
                HStack {
                    SecureField("App-specific password", text: $password).textContentType(.password)
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { password = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                Text("\(provider.name) needs a password just for Joshu")
            } footer: {
                Text(provider.inApp
                     ? "\(provider.name)'s page opens here. Sign in, make a password named \"Joshu\", and tap Copy: Joshu fills it in and connects. Your real password is never used; the app password stays in the Keychain on this device."
                     : "Sign in on \(provider.name)'s page, make a password named \"Joshu\" and copy it, then come back and tap the paste button. Your real password is never used; the app password stays in the Keychain on this device.")
            }
        }
    }

    private var otherSection: some View {
        Section {
            TextField("IMAP server (e.g. imap.example.com)", text: $host)
                #if os(iOS)
                .keyboardType(.URL).textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("Port", text: $port)
            SecureField("Password or app password", text: $password).textContentType(.password)
        } header: {
            Text("Your provider's details")
        } footer: {
            Text(provider.steps.joined(separator: " "))
        }
    }

    // MARK: Actions

    private func signIn() async {
        checking = true
        problem = nil
        defer { checking = false }
        if providerID == "gmail" {
            await inbox.addAccount(hint: validEmail ? email : nil)
            if let e = inbox.error { problem = e } else { added(); dismiss() }
            return
        }
        do {
            let account = try await MicrosoftMail.signIn(hint: validEmail ? email : nil)
            IMAPMail.add(account)
            added()
            dismiss()
        } catch is CancellationError {
        } catch {
            problem = error.localizedDescription
        }
    }

    private func connect() async {
        guard !checking else { return }
        checking = true
        problem = nil
        defer { checking = false }
        do {
            let account = try await IMAPMail.connect(email: email, password: password, provider: providerID,
                                                     host: providerID == "other" ? host : provider.host, port: Int(port) ?? 993)
            IMAPMail.add(account, password: password)
            added()
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// A provider's app-password page inside Joshu. When you copy the new password there, Joshu notices it on the
/// clipboard and hands it back, so there's nothing to paste.
struct PasswordPageSheet: View {
    let url: URL
    let providerName: String
    var caught: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startCount = PasswordPageSheet.changeCount

    private static var changeCount: Int {
        #if os(iOS)
        UIPasteboard.general.changeCount
        #else
        NSPasteboard.general.changeCount
        #endif
    }

    private static var clipboard: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make a password for Joshu").font(Theme.ui(15, weight: .semibold))
                    Text(providerName == "iCloud Mail"
                         ? "Sign in, open App-Specific Passwords, tap +, name it Joshu, then tap Copy. Joshu takes it from there."
                         : "Sign in, make an app password named Joshu, then tap Copy. Joshu takes it from there.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            .padding(14)
            .background(Theme.lime.opacity(0.35))
            WebPage(url: url)
        }
        .sheetFrame(width: 720, height: 760)
        .task {
            // Watch the clipboard while the page is open: copying a fresh app password ends the sheet.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let count = Self.changeCount
                guard count != startCount else { continue }
                startCount = count
                if let s = Self.clipboard, IMAPMail.looksLikeAppPassword(s) {
                    caught(s.trimmingCharacters(in: .whitespacesAndNewlines))
                    return
                }
            }
        }
    }
}

/// A plain web page (WKWebView).
struct WebPage {
    let url: URL
    fileprivate func makeView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let v = WKWebView(frame: .zero, configuration: config)
        v.load(URLRequest(url: url))
        return v
    }
}

#if os(iOS)
extension WebPage: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#else
extension WebPage: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeView() }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif
