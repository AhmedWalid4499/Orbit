import SwiftUI
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

/// Settings › Connections: email accounts Joshu reads straight from the mail server (iCloud, Gmail, Yahoo, others),
/// on iPhone and Mac, with an app-specific password kept in the Keychain.
struct EmailAccountsConnection: View {
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var pro = Pro.shared
    @State private var adding = false
    @State private var accounts = IMAPMail.accounts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.pink)
                    .overlay(Image(systemName: "at").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email accounts").font(.headline)
                    Text(accounts.isEmpty
                         ? "Sum up your inbox on Today, read emails and draft replies, right on this device. Works with iCloud, Gmail, Yahoo and most email."
                         : "Joshu reads these inboxes directly (it never marks anything read) for the summary on Today.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            ForEach(accounts) { a in
                HStack {
                    Image(systemName: "envelope").foregroundStyle(.secondary)
                    Text(a.email).font(Theme.ui(13)).lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        IMAPMail.remove(a.email)
                        accounts = IMAPMail.accounts
                        inbox.emailAccountsChanged()
                    }
                    .font(Theme.ui(12))
                }
            }
            Button {
                if !pro.canAddEmail(existing: accounts.count) { AppState.current?.openPro() } else { adding = true }
            } label: { Label(accounts.isEmpty ? "Connect an email account" : "Add another account", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) {
            AddEmailAccountSheet { accounts = IMAPMail.accounts; inbox.emailAccountsChanged() }
        }
    }
}

/// Pick the provider, follow the steps to make an app-specific password, paste it, and Joshu checks it signs in.
struct AddEmailAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    var added: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var providerID = "icloud"
    @State private var host = ""
    @State private var port = "993"
    @State private var checking = false
    @State private var problem: String?
    @State private var pickedByHand = false

    private var provider: IMAPMail.Provider { IMAPMail.providers.first { $0.id == providerID } ?? IMAPMail.providers[0] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $providerID) {
                        ForEach(IMAPMail.providers) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: providerID) { _, _ in pickedByHand = true }
                    TextField("Email address", text: $email)
                        .textContentType(.username)
                        #if os(iOS)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onChange(of: email) { _, new in
                            if !pickedByHand, new.contains("@") { providerID = IMAPMail.guessProvider(new) }
                        }
                    if providerID == "other" {
                        TextField("IMAP server (e.g. imap.example.com)", text: $host)
                            #if os(iOS)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        TextField("Port", text: $port)
                    }
                    SecureField(providerID == "other" ? "Password or app password" : "App-specific password", text: $password)
                        .textContentType(.password)
                } footer: {
                    if IMAPMail.isMicrosoft(email) {
                        Text("Outlook and Hotmail don't allow app passwords any more, so they can't be connected here yet. On a Mac, add the account to Apple Mail and connect Apple Mail.")
                            .foregroundStyle(Theme.orange)
                    }
                }
                Section {
                    ForEach(Array(provider.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)").font(Theme.ui(12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                .frame(width: 20, height: 20).background(Circle().fill(Theme.lime))
                            Text(step).font(Theme.ui(13)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let page = provider.passwordPage {
                        Button { Platform.open(page) } label: { Label("Open \(provider.name)'s password page", systemImage: "arrow.up.right.square") }
                    }
                } header: {
                    Text(providerID == "other" ? "Your provider's details" : "Make an app-specific password")
                } footer: {
                    Text("It's a separate password just for Joshu: your real password is never used, and you can delete it any time from the same page. It stays in the Keychain on this device, and Joshu connects straight to your email provider.")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(checking ? "Checking…" : "Connect") { Task { await connect() } }
                        .disabled(checking || !email.contains("@") || password.isEmpty || IMAPMail.isMicrosoft(email) || (providerID == "other" && host.isEmpty))
                }
            }
        }
        .sheetFrame(width: 520, height: 640)
    }

    private func connect() async {
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
