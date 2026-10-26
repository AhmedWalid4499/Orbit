import SwiftUI

/// What you see after signing out (Mac and iPhone): Welcome to Joshu, with creating an account, signing in, or
/// carrying on without one. It goes away as soon as you're signed in.
struct SignedOutWelcome: View {
    /// Set when you sign out; cleared when you sign in or choose to carry on without an account.
    static let key = "auth.welcome"

    @AppStorage(SignedOutWelcome.key) private var showing = false
    @ObservedObject private var cloud = CloudSync.shared
    @State private var appeared = false

    private let points: [(String, String, Color)] = [
        ("arrow.triangle.2.circlepath", "Your tasks, money, books and ideas on your Mac and iPhone, always in sync", Theme.lime),
        ("sparkles", "An assistant you name yourself, that knows your day and gets things done", Theme.pink),
        ("lock.fill", "Backed up to your account, and only you can see it", Theme.cyan),
    ]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            // Soft blobs in the orb's colours behind everything.
            GeometryReader { g in
                ZStack {
                    Circle().fill(Theme.lime.opacity(0.55)).frame(width: g.size.width * 0.7).blur(radius: 90)
                        .offset(x: -g.size.width * 0.3, y: -g.size.height * 0.3)
                    Circle().fill(Theme.cyan.opacity(0.35)).frame(width: g.size.width * 0.6).blur(radius: 100)
                        .offset(x: g.size.width * 0.35, y: g.size.height * 0.25)
                    Circle().fill(Theme.pink.opacity(0.3)).frame(width: g.size.width * 0.45).blur(radius: 90)
                        .offset(x: g.size.width * 0.1, y: g.size.height * 0.45)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            GeometryReader { g in
                ScrollView {
                    AdaptiveStack(spacing: Platform.isPhone ? 28 : 56) {
                        intro.frame(maxWidth: 440, alignment: .leading)
                        signIn.frame(maxWidth: 400)
                    }
                    .padding(.horizontal, Platform.isPhone ? 24 : 56)
                    .padding(.vertical, Platform.isPhone ? 36 : 60)
                    // Centred in the window when it fits; scrolls when it doesn't.
                    .frame(maxWidth: .infinity, minHeight: g.size.height)
                }
                .scrollIndicators(.never)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        .onChange(of: cloud.email) { _, email in if email != nil { showing = false } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("joshu").font(.system(size: Platform.isPhone ? 46 : 56, weight: .black, design: .rounded)).tracking(-1.5)
                OrbDot(size: Platform.isPhone ? 14 : 17).alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to Joshu").font(Theme.display(Platform.isPhone ? 34 : 42)).fixedSize(horizontal: false, vertical: true)
                Text("Your whole life, in one calm place. Create an account or sign in to bring everything back.")
                    .font(Theme.ui(16)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(points, id: \.1) { symbol, text, tint in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 28, height: 28).background(Circle().fill(tint))
                        Text(text).font(Theme.ui(15)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                }
            }
        }
    }

    private var signIn: some View {
        VStack(spacing: 14) {
            AuthPanel()
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.canvas.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
            Button("Use Joshu without an account") { withAnimation { showing = false } }
                .buttonStyle(.orbitLink).font(Theme.ui(14, weight: .medium))
        }
    }
}
