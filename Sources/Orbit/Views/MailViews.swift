import SwiftUI

/// One email, read in Orbit, with a reply box: type it yourself or let the assistant draft it, then send.
struct MailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AIAssistant.shared
    let id: String
    let account: String

    @State private var message: MailMessage?
    @State private var error: String?
    @State private var reply = ""
    @State private var intent = ""
    @State private var drafting = false
    @State private var sending = false
    @State private var sent = false
    @State private var needsPermission = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(message?.subject.isEmpty == false ? message!.subject : "Email").font(Theme.display(22)).lineLimit(2)
                Spacer()
                if let message, let u = InboxStore.link(.init(account: account, from: "", subject: "", note: "", messageID: message.id)) {
                    Button { Platform.open(u) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).help("Open in Gmail")
                }
                Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            .padding(20)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let m = message {
                        HStack(spacing: 10) {
                            Text(String(m.sender.prefix(1)).uppercased()).font(Theme.ui(15, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                .frame(width: 38, height: 38).background(Circle().fill(Theme.pink))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.sender).font(Theme.ui(14, weight: .semibold))
                                Text("\(m.fromAddress)\(m.date.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")")
                                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            }
                        }
                        Text(m.body.isEmpty ? "(This email has no text. Open it in Gmail to see it.)" : m.body)
                            .font(Theme.ui(14)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(13)).foregroundStyle(Theme.orange)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    }
                }
                .padding(20)
            }
            if message != nil { composer }
        }
        .sheetFrame(width: 620, height: 720)
        .task { await load() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sent {
                Label("Sent", systemImage: "checkmark.circle.fill").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.good)
            } else {
                if ai.hasKey {
                    HStack(spacing: 8) {
                        AssistantAvatar(size: 22)
                        TextField("What do you want to say? (e.g. yes, 8:30 works)", text: $intent).textFieldStyle(.plain).font(Theme.ui(13))
                            .onSubmit(draft)
                        Button(drafting ? "Writing…" : "Draft reply", action: draft).buttonStyle(SoftButtonStyle()).disabled(drafting)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                }
                TextEditor(text: $reply)
                    .font(Theme.ui(14)).scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    .overlay(alignment: .topLeading) {
                        if reply.isEmpty {
                            Text("Write a reply…").font(Theme.ui(14)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 13).padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                if let error, message != nil {
                    Text(error).font(Theme.ui(12)).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if needsPermission {
                        Button("Allow sending") { Task { await allow() } }.buttonStyle(SoftButtonStyle())
                    }
                    Spacer()
                    Button { Task { await send() } } label: {
                        Label(sending ? "Sending…" : "Send", systemImage: "paperplane.fill").frame(minWidth: 100)
                    }
                    .buttonStyle(PrimaryButtonStyle()).fixedSize()
                    .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .background(Theme.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func load() async {
        do { message = try await MailReader.message(id, account: account) } catch { self.error = error.localizedDescription }
    }

    private func draft() {
        guard let m = message, !drafting else { return }
        drafting = true
        Task {
            // Notes typed in the reply box count too, so "Draft reply" turns them into a real email.
            let notes = intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reply : intent
            do { reply = try await MailReader.draftReply(to: m, intent: notes) } catch { self.error = error.localizedDescription }
            drafting = false
        }
    }

    private func send() async {
        guard let m = message else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await MailReader.reply(to: m, body: reply)
            sent = true
        } catch let e as MailReader.NeedsPermission {
            needsPermission = true
            error = e.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func allow() async {
        do {
            _ = try await GoogleAuth.signIn(hint: account)
            needsPermission = false
            error = nil
            await send()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Recent inbox mail from all your Gmail accounts; tap one to read and reply.
struct MailboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inbox = InboxStore.shared
    @State private var items: [MailListItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var open: MailListItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox").font(Theme.display(26))
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(loading)
                Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            .padding(20)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                    if loading && items.isEmpty { ProgressView().padding(40) }
                    ForEach(items) { m in
                        Button { open = m } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(m.unread ? Theme.cyan : .clear).frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(m.from).font(Theme.ui(13, weight: m.unread ? .bold : .semibold)).lineLimit(1)
                                        Spacer()
                                        if let d = m.date { Text(Fmt.relativeDay(d) == "Today" ? Fmt.time(d) : Fmt.relativeDay(d)).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted) }
                                    }
                                    Text(m.subject).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                                    Text(m.snippet).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(2).multilineTextAlignment(.leading)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .sheetFrame(width: 560, height: 700)
        .task { await load() }
        .sheet(item: $open) { m in MailSheet(id: m.id, account: m.account) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { items = try await MailReader.recent(accounts: inbox.accounts); error = nil } catch { self.error = error.localizedDescription }
    }
}
