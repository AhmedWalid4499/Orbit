import SwiftUI
import SwiftData
import PhotosUI

/// Settings on iPhone: the Mac's settings sections, as pages.
struct PhoneSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @ObservedObject private var ai = AIAssistant.shared
    @ObservedObject private var profile = ProfileStore.shared
    @AppStorage("userName") private var userName = ""
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Avatar(name: userName.isEmpty ? "Me" : userName, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(userName.isEmpty ? "Your name" : userName).font(Theme.ui(17, weight: .semibold))
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text(profile.photo == nil ? "Add a photo" : "Change photo").font(Theme.ui(13))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    page("Account & sync", "person.crop.circle.fill", Theme.cyan, detail: cloud.email ?? "Not signed in") { AccountSettings() }
                    page("AI", "sparkles", Theme.lime, detail: ai.hasKey ? AssistantName.current : "Add your API key") { AISettings() }
                    page("Connections", "link", Theme.purple, detail: nil) { PhoneConnections() }
                    page("Notifications", "bell.fill", Theme.orange, detail: nil) { NotificationSettingsView() }
                    page("General", "gearshape.fill", Theme.card, detail: nil) { GeneralSettings() }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } footer: {
                    Text("Orbit on iPhone shares everything with Orbit on your Mac through your Orbit account. Sign in with the same account on both.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photo) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { profile.setPhoto(image) }
                }
            }
        }
    }

    private func page<Content: View>(_ title: String, _ symbol: String, _ color: Color, detail: String?, @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigationLink {
            content().formStyle(.grouped).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(color))
                Text(title).font(Theme.ui(16, weight: .medium))
                Spacer()
                if let detail { Text(detail).font(Theme.ui(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
        }
    }
}

/// First launch: sign in to the same Orbit account as the Mac, then unlock synced keys.
struct PhoneWelcome: View {
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSync.shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OrbitMark(size: 72).padding(.top, 40)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Orbit on your iPhone").font(Theme.display(34))
                    Text("Sign in with the account you use on your Mac and everything comes across: tasks, calendar, habits, money, notes, books, trips and your assistant.")
                        .font(Theme.ui(15)).foregroundStyle(Theme.inkSecondary)
                }
                if !cloud.isSignedIn {
                    Button {
                        run { try await cloud.signInWithGoogle(context: context) }
                    } label: {
                        Label("Continue with Google", systemImage: "g.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    VStack(spacing: 10) {
                        TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        SecureField("Password", text: $password).textContentType(.password)
                    }
                    .textFieldStyle(.roundedBorder)
                    Button("Sign in with email") { run { try await cloud.signIn(email: email, password: password, context: context) } }
                        .buttonStyle(SoftButtonStyle()).disabled(email.isEmpty || password.isEmpty)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Signed in as \(cloud.email ?? "")", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                        if cloud.syncing { Label("Bringing everything over from your Mac…", systemImage: "arrow.triangle.2.circlepath").font(Theme.ui(13)) }
                        else if let s = cloud.status { Text(s).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary) }
                        if cloud.vaultState == .waiting {
                            Text("Open Orbit on your Mac once so your API key and Google and GitHub sign-ins come across.").font(Theme.ui(13))
                        }
                        Button("Start", action: onDone).buttonStyle(PrimaryButtonStyle())
                    }
                }
                if busy { ProgressView() }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(13)).foregroundStyle(Theme.orange) }
                if !cloud.isSignedIn {
                    Button("Use Orbit without an account", action: onDone).buttonStyle(.borderless).font(Theme.ui(14))
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true; error = nil
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// Quick add: type or say anything; Orbit files it as a task, event, expense, note or journal line.
struct PhoneCapture: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var ai = AIAssistant.shared
    @ObservedObject private var dictation = Dictation.shared
    @State private var text = ""
    @State private var busy = false
    @State private var result: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick add").font(Theme.display(26))
                Spacer()
                Button("Done") { dismiss() }
            }
            HStack(alignment: .top, spacing: 10) {
                if dictation.listening {
                    Text(dictation.text.isEmpty ? "Listening…" : dictation.text).font(Theme.ui(17))
                        .foregroundStyle(dictation.text.isEmpty ? Theme.inkMuted : Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("“Dentist Thursday at 3”, “$12 lunch”, “call mom tomorrow !!”", text: $text, axis: .vertical)
                        .font(Theme.ui(17)).lineLimit(1...5).focused($focused).submitLabel(.done)
                        .onSubmit(save)
                }
                MicButton { heard in text = heard; save() }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            if !text.isEmpty && !ai.smartCaptureActive {
                Text(QuickParser.parse(text).summary).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            Button(action: save) {
                Label(busy ? "Saving…" : "Add", systemImage: ai.smartCaptureActive ? "sparkles" : "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            if let result { Label(result, systemImage: "checkmark.circle.fill").font(Theme.ui(14, weight: .medium)).foregroundStyle(Theme.good) }
            if let e = dictation.error { Text(e).font(Theme.ui(12)).foregroundStyle(Theme.orange) }
            Text("One line can hold several things: “gym tomorrow 7am and pay rent friday”.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            Spacer()
        }
        .padding(20)
        .onAppear { focused = true }
    }

    private func save() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !busy else { return }
        busy = true
        Task {
            let summary = await CaptureEngine.capture(raw, context: context)
            busy = false
            text = ""
            withAnimation { result = summary.isEmpty ? "Nothing to add" : "Added: \(summary)" }
        }
    }
}

/// My Card, with a Done button and a photo picker on iPhone.
struct PhoneCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = ProfileStore.shared
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ProfileCardSheet()
                .navigationTitle("My Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "person.crop.circle.badge.plus") }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .onChange(of: photo) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { profile.setPhoto(image) }
                    }
                }
        }
    }
}
