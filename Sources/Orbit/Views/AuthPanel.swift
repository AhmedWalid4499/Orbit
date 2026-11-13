import SwiftUI
import SwiftData

/// Sign in to your Joshu account with Apple (Apple's own sheet on iPhone, Apple's web page on the Mac); email stays behind
/// a small link (accounts first made with Google can use "Forgot password?" there to set one). Until the sync server has
/// Sign in with Apple switched on, email is shown. Google sign-in is off for the App Store release (the code stays). Used in the first-launch welcome on Mac and iPhone and in Settings › Account.
struct AuthPanel: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSync.shared
    @State private var creating = true
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var isError = false
    @State private var googleTask: Task<Void, Never>?

    /// Whether the sync server has Sign in with Apple switched on (nil while asking).
    @State private var appleReady: Bool? = Snapshot.isDemo ? true : nil
    @State private var showOther = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appleReady == true {
                // Sign in with Apple; email stays behind a small link.
                appleButton
                Button(showOther ? "Hide email sign-in" : "Use email instead") {
                    withAnimation(.snappy) { showOther.toggle(); message = nil }
                }
                .buttonStyle(.orbitLink).font(Theme.ui(12))
                if showOther {
                    Picker("", selection: $creating) {
                        Text("Create account").tag(true)
                        Text("Sign in").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .onChange(of: creating) { message = nil }
                    emailFields(create: creating)
                }
            } else if appleReady == false {
                // Until Apple is switched on for the sync server, the earlier ways keep working.
                Picker("", selection: $creating) {
                    Text("Create account").tag(true)
                    Text("Sign in").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: creating) { message = nil }
                emailFields(create: creating)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10)
            }

            if let message {
                Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "envelope.fill")
                    .font(Theme.ui(12)).foregroundStyle(isError ? Theme.orange : Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Your account keeps your data in sync between your devices and backs it up. Only you can see it.")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .task {
            if appleReady == nil { appleReady = await CloudAuth.enabledProviders().contains("apple") }
        }
    }

    @ViewBuilder
    private var appleButton: some View {
        if AppleSignIn.available {
            AppleSignInButton(working: working) { token, nonce, name in apple(token, nonce, name) } onError: { show($0, error: true) }
        } else {
            WebAppleSignInButton(working: working, action: appleOnWeb)
        }
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text("or").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private var cancelGoogle: some View {
        if let googleTask {
            Button("Cancel") { googleTask.cancel() }.buttonStyle(.orbitLink).font(Theme.ui(12))
        }
    }

    @ViewBuilder
    private func emailFields(create: Bool) -> some View {
        VStack(spacing: 10) {
            field {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    #if os(iOS)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
            }
            field {
                SecureField(create ? "Password (at least 6 characters)" : "Password", text: $password)
                    .textContentType(create ? .newPassword : .password)
                    .onSubmit(submit)
            }
        }
        Button(action: submit) {
            HStack {
                if working { ProgressView().controlSize(.small).tint(Theme.onInverse) }
                Text(create ? "Create account" : "Sign in")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(working || !email.contains("@") || password.count < 6)
        if !create {
            Button("Forgot password?") {
                Task {
                    do { try await CloudAuth.resetPassword(email: email); show("Check \(email) for a link to reset your password.") }
                    catch { show(error.localizedDescription, error: true) }
                }
            }
            .buttonStyle(.orbitLink).font(Theme.ui(12)).disabled(!email.contains("@"))
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain).font(Theme.ui(15))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }

    private func show(_ text: String, error: Bool = false) { message = text; isError = error }

    private func google() {
        working = true; message = nil
        googleTask = Task {
            defer { working = false; googleTask = nil }
            do { try await cloud.signInWithGoogle(context: context) }
            catch is CancellationError {}
            catch { show(error.localizedDescription, error: true) }
        }
    }

    private func appleOnWeb() {
        working = true; message = nil
        Task {
            defer { working = false }
            do { try await cloud.signInWithAppleOnWeb(context: context) }
            catch is CancellationError {}
            catch { show(error.localizedDescription, error: true) }
        }
    }

    private func apple(_ token: String, _ nonce: String, _ name: String?) {
        working = true; message = nil
        Task {
            defer { working = false }
            do { try await cloud.signInWithApple(idToken: token, nonce: nonce, name: name, context: context) }
            catch { show(error.localizedDescription, error: true) }
        }
    }

    private func submit() {
        guard !working, email.contains("@"), password.count >= 6 else { return }
        working = true; message = nil
        let e = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { working = false }
            do {
                if creating {
                    switch try await cloud.signUp(email: e, password: password, context: context) {
                    case .signedIn: password = ""
                    case .checkEmail:
                        show("Almost done: open the email we sent to \(e), tap the link, then sign in here.")
                        creating = false
                    }
                } else {
                    try await cloud.signIn(email: e, password: password, context: context)
                    password = ""
                }
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }
}

/// The standard white "Sign in with Google" button with the four-colour G.
struct GoogleSignInButton: View {
    var working = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleG().frame(width: 18, height: 18)
                Text("Sign in with Google").font(.system(size: 15, weight: .medium))
                if working { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(scheme == .dark ? Color(hex: 0xE3E3E3) : Color(hex: 0x1F1F1F))
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(scheme == .dark ? Color(hex: 0x131314) : .white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(scheme == .dark ? Color(hex: 0x8E918F) : Color(hex: 0x747775), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}

/// Google's "G" mark, drawn.
struct GoogleG: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height), w = s * 0.2, r = (s - w) / 2
            ZStack {
                arc(-40, 50, Color(hex: 0x4285F4), r, w)    // blue, right
                arc(50, 140, Color(hex: 0x34A853), r, w)    // green, bottom
                arc(140, 215, Color(hex: 0xFBBC05), r, w)   // yellow, left
                arc(215, 320, Color(hex: 0xEA4335), r, w)   // red, top
                Rectangle().fill(Color(hex: 0x4285F4)).frame(width: s * 0.47, height: w)
                    .offset(x: s * 0.235 - w * 0.25)
            }
            .frame(width: s, height: s)
        }
    }

    private func arc(_ from: Double, _ to: Double, _ c: Color, _ r: CGFloat, _ w: CGFloat) -> some View {
        Circle().trim(from: from < 0 ? (360 + from) / 360 : from / 360, to: from < 0 ? 1 : to / 360)
            .stroke(c, style: StrokeStyle(lineWidth: w))
            .frame(width: r * 2, height: r * 2)
            .overlay {
                if from < 0 {
                    Circle().trim(from: 0, to: to / 360).stroke(c, style: StrokeStyle(lineWidth: w)).frame(width: r * 2, height: r * 2)
                }
            }
    }
}

/// "Sign in with Apple" for the Mac, in Apple's style (black, or white in dark mode), opening Apple's page in a browser window.
struct WebAppleSignInButton: View {
    var working = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "apple.logo").font(.system(size: 16, weight: .medium))
                Text("Sign in with Apple").font(.system(size: 15, weight: .medium))
                if working { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(scheme == .dark ? Color.black : .white)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(scheme == .dark ? Color.white : .black))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}
