import SwiftUI
import SwiftData

/// Sign in or create an Orbit account: email first (Create account / Sign in), then the usual
/// "Sign in with Google" button. Used in the first-launch welcome on Mac and iPhone and in Settings › Account.
struct AuthPanel: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSync.shared
    @State private var creating = true
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $creating) {
                Text("Create account").tag(true)
                Text("Sign in").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: creating) { message = nil }

            VStack(spacing: 10) {
                field {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        #if os(iOS)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                }
                field {
                    SecureField(creating ? "Password (at least 6 characters)" : "Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .onSubmit(submit)
                }
            }

            Button(action: submit) {
                HStack {
                    if working { ProgressView().controlSize(.small).tint(Theme.onInverse) }
                    Text(creating ? "Create account" : "Sign in")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working || !email.contains("@") || password.count < 6)
            .keyboardShortcut(.defaultAction)

            if !creating {
                Button("Forgot password?") {
                    Task {
                        do { try await CloudAuth.resetPassword(email: email); show("Check \(email) for a link to reset your password.") }
                        catch { show(error.localizedDescription, error: true) }
                    }
                }
                .buttonStyle(.orbitLink).font(Theme.ui(12)).disabled(!email.contains("@"))
            }

            HStack(spacing: 10) {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text("or").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                Rectangle().fill(Theme.line).frame(height: 1)
            }

            GoogleSignInButton(working: working, action: google)

            if let message {
                Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "envelope.fill")
                    .font(Theme.ui(12)).foregroundStyle(isError ? Theme.orange : Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Your account keeps your data in sync between your devices and backs it up. Only you can see it.")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
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
        Task {
            defer { working = false }
            do { try await cloud.signInWithGoogle(context: context) }
            catch is CancellationError {}
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
