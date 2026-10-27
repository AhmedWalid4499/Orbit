import SwiftUI
import SwiftData

/// Setting up a new account, one question at a time (Mac and iPhone): what to call you, your preferences,
/// what to connect, and what to call your assistant.
struct SetupFlow: View {
    /// Set when a brand-new account signs in; cleared when the setup is finished.
    static let key = "setupNeeded"

    var onDone: () -> Void = {}

    init(startAt: Int = 0, onDone: @escaping () -> Void = {}) {
        self.onDone = onDone
        _step = State(initialValue: startAt)
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var health = HealthStore.shared
    @ObservedObject private var pro = Pro.shared

    @AppStorage("userName") private var userName = ""
    @AppStorage("assistantName") private var assistantName = "Joshu"
    @AppStorage("currencyCode") private var currency = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("monthlyBudget") private var budget = 2000.0
    @AppStorage("weatherCity") private var city = ""
    @AppStorage("readingGoal") private var readingGoal = 24
    @AppStorage("hiddenTabs") private var hiddenRaw = ""

    @State private var step = 0
    @State private var name = ""
    @State private var aiName = ""
    @State private var forward = true

    private let steps = ["You", "Preferences", "Connect", "Assistant"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch step {
                    case 0: nameStep
                    case 1: preferencesStep
                    case 2: connectStep
                    default: assistantStep
                    }
                }
                .padding(.horizontal, Platform.isPhone ? 24 : 40).padding(.vertical, 24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity))
            }
            .scrollIndicators(.never)
            footer
        }
        .background(Theme.canvas.ignoresSafeArea())
        .sheetFrame(width: 620, height: 640)
        .interactiveDismissDisabled()
        .onAppear {
            name = userName.isEmpty ? Platform.userName : userName
            aiName = assistantName
        }
    }

    // MARK: Frame

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= step ? Theme.ink : Theme.ink.opacity(0.14)).frame(height: 4)
                }
            }
            HStack {
                Text("Step \(step + 1) of \(steps.count) · \(steps[step])").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Platform.isPhone ? 24 : 40).padding(.top, Platform.isPhone ? 16 : 26)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(step - 1) }.buttonStyle(.orbitLink).font(Theme.ui(14))
            }
            Spacer()
            Button(step == steps.count - 1 ? "Start using Joshu" : "Continue") {
                step == steps.count - 1 ? finish() : go(step + 1)
            }
            .buttonStyle(PrimaryButtonStyle()).frame(width: 200)
            .keyboardShortcut(.defaultAction)
            .disabled(step == 0 && name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Platform.isPhone ? 24 : 40).padding(.vertical, 18)
    }

    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(Theme.display(Platform.isPhone ? 30 : 34)).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(Theme.ui(15)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).font(Theme.ui(18, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    // MARK: Steps

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("joshu").font(.system(size: 40, weight: .black, design: .rounded)).tracking(-1)
                OrbDot(size: 13).alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            }
            title("What should we call you?", "Joshu greets you by name and uses it in your morning brief.")
            field("Your name", text: $name).onSubmit { if !name.isEmpty { go(1) } }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("A few preferences", "So money, weather and reading look right from day one. You can change any of these in Settings.")
            VStack(spacing: 0) {
                prefRow("Currency", "banknote.fill", Theme.mint) {
                    Picker("", selection: $currency) {
                        ForEach(["USD", "EUR", "GBP", "EGP", "AED", "SAR", "KWD", "QAR", "JPY", "CAD", "AUD", "INR"], id: \.self) { Text($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                prefRow("Monthly budget", "chart.pie.fill", Theme.peach) {
                    TextField("2000", value: $budget, format: .number).multilineTextAlignment(.trailing).frame(width: 110)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Divider()
                prefRow("Weather city", "cloud.sun.fill", Theme.cyan) {
                    TextField(WeatherStore.defaultCity, text: $city).multilineTextAlignment(.trailing).frame(maxWidth: 170)
                }
                Divider()
                prefRow("Books a year", "books.vertical.fill", Theme.purple) {
                    Stepper("\(readingGoal)", value: $readingGoal, in: 1...200).fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))

            VStack(alignment: .leading, spacing: 10) {
                Text("What will you use?").font(Theme.ui(14, weight: .semibold))
                FlowLayout(spacing: 6) {
                    ForEach(Tab.allCases.filter(\.canHide)) { t in
                        let on = !hiddenSet.contains(t)
                        Label(t == .reading ? "Reading" : t.title, systemImage: t.symbol).font(Theme.ui(13, weight: .medium))
                            .foregroundStyle(on ? Theme.onInverse : Theme.inkSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Capsule().fill(on ? Theme.inverse : Theme.card))
                            .contentShape(Capsule())
                            .onTapGesture { toggle(t, on: on) }
                    }
                }
                Text("Tap to hide what you won't use. Everything stays one tap away in Settings.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Bring in your day", "Connect what you already use, and Joshu fills itself in. Skip anything and connect it later in Settings.")
            VStack(spacing: 10) {
                connectRow("calendar", "Calendar & Reminders", "Your events, including Outlook and Google calendars on this device",
                           Theme.cyan, done: apple.calendarEnabled) {
                    Task { await apple.connectCalendar(); await apple.connectReminders() }
                }
                if GoogleAuth.isConfigured {
                    connectRow("envelope.fill", "Gmail & Google Calendar",
                               inbox.accounts.isEmpty ? "Receipts, bookings and what needs a reply" : inbox.accounts.joined(separator: ", "),
                               Theme.pink, done: !inbox.accounts.isEmpty) {
                        Task { await inbox.addAccount() }
                    }
                }
                #if os(iOS)
                if health.available {
                    connectRow("heart.fill", "Apple Health", "Steps, sleep and workouts next to your habits", Theme.peach, done: health.connected) {
                        Task { await health.connect(context: context) }
                    }
                }
                #endif
            }
        }
    }

    private var assistantStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Spacer(); AssistantAvatar(size: 84, busy: true); Spacer() }
            title("Name your assistant", "It plans with you, writes, searches and gets things done. Call it anything you like.")
            field("Joshu", text: $aiName).onSubmit(finish)
            if !pro.isPro {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.lime))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your assistant comes with Joshu Pro").font(Theme.ui(14, weight: .semibold))
                        Text("Everything else in Joshu is free. Upgrade whenever you like and \(aiNameOrDefault) will be ready.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        Button("See Joshu Pro") { finish(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AppState.current?.proOpen = true } }
                            .buttonStyle(.orbitLink).font(Theme.ui(13, weight: .semibold)).padding(.top, 2)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            }
        }
    }

    // MARK: Pieces

    private func prefRow<Control: View>(_ label: String, _ symbol: String, _ tint: Color, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 28, height: 28).background(Circle().fill(tint))
            Text(label).font(Theme.ui(15, weight: .medium))
            Spacer(minLength: 10)
            control().font(Theme.ui(15))
        }
        .padding(.vertical, 11)
    }

    private func connectRow(_ symbol: String, _ title: String, _ detail: String, _ tint: Color, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.ui(15, weight: .semibold))
                Text(detail).font(Theme.ui(12.5)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if done {
                Label("Connected", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).font(.system(size: 22)).foregroundStyle(Theme.good)
            } else {
                Button("Connect", action: action).buttonStyle(SoftButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }

    private var hiddenSet: Set<Tab> { Set(hiddenRaw.split(separator: ",").compactMap { Tab(rawValue: String($0)) }) }

    private func toggle(_ t: Tab, on: Bool) {
        var h = Tab.hidden
        if on { h.insert(t) } else { h.remove(t) }
        Tab.hidden = h
        hiddenRaw = UserDefaults.standard.string(forKey: "hiddenTabs") ?? ""
    }

    private var aiNameOrDefault: String {
        let n = aiName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Joshu" : n
    }

    private func go(_ i: Int) {
        if step == 0 { userName = name.trimmingCharacters(in: .whitespaces) }
        forward = i > step
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = max(0, min(steps.count - 1, i)) }
    }

    private func finish() {
        userName = name.trimmingCharacters(in: .whitespaces).isEmpty ? userName : name.trimmingCharacters(in: .whitespaces)
        assistantName = aiNameOrDefault
        UserDefaults.standard.set(false, forKey: Self.key)
        onDone()
    }
}
