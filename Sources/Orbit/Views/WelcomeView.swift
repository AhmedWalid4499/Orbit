import SwiftUI

/// First launch on a new Mac, and a brand-new account: sign in or create an account, then set up step by step.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("onboarded") private var onboarded = false
    @ObservedObject private var cloud = CloudSync.shared
    @State private var accountStep = SupabaseConfig.isConfigured && CloudSync.shared.email == nil

    var body: some View {
        if accountStep { accountPage } else { SetupFlow { onboarded = true; dismiss() } }
    }

    /// Step 1: sign in or create an account (skippable).
    private var accountPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OrbitMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Joshu").font(Theme.display(30))
                    Text("Create an account to keep everything in sync and backed up.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
            }
            AuthPanel()
            HStack {
                Spacer()
                Button("Skip for now") { withAnimation { accountStep = false } }.buttonStyle(.orbitLink).font(Theme.ui(13))
            }
        }
        .padding(30)
        .sheetFrame(width: 480)
        .interactiveDismissDisabled()
        .onChange(of: cloud.email) { _, e in if e != nil { withAnimation { accountStep = false } } }
    }

}
