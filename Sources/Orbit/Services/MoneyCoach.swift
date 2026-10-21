import Foundation
import SwiftUI
import SwiftData

/// Claude looks at the last three months of spending and suggests concrete ways to save.
@MainActor
final class MoneyCoach: ObservableObject {
    static let shared = MoneyCoach()

    struct Tip: Codable, Equatable, Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let monthly_saving: Double
    }
    struct Advice: Codable, Equatable {
        let headline: String
        let tips: [Tip]
        var generatedAt: Date = .now

        enum CodingKeys: String, CodingKey { case headline, tips, generatedAt }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            headline = try c.decode(String.self, forKey: .headline)
            tips = try c.decode([Tip].self, forKey: .tips)
            generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
        }
    }

    @Published private(set) var advice: Advice?
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private let cacheKey = "moneyCoachCache"

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey) { advice = try? JSONDecoder().decode(Advice.self, from: data) }
    }

    /// Refreshes once a day when Money is opened; `force` for the refresh button.
    func refresh(context: ModelContext, force: Bool = false) async {
        guard !loading, !Snapshot.isActive, AIAssistant.shared.hasKey, let claude = ClaudeClient() else { return }
        if !force, let a = advice, a.generatedAt.isToday { return }
        let txns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        guard txns.contains(where: \.isExpense) else { return }

        loading = true
        error = nil
        defer { loading = false }
        let system = """
        You are a practical, kind money coach inside a personal budgeting app. Look at the spending data and suggest specific ways to save.
        - headline: one short sentence on how this month is going compared with the budget and previous months.
        - tips: 3-4 concrete actions based on THIS data (name the merchants, categories and subscriptions involved), each with a realistic monthly_saving in the user's currency (\(Fmt.currencyCode)). detail is 1-2 sentences. No generic advice like "make a budget".
        Don't shame; be encouraging. Plain text, no markdown.
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headline": ["type": "string"],
                "tips": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["title": ["type": "string"], "detail": ["type": "string"], "monthly_saving": ["type": "number"]],
                    "required": ["title", "detail", "monthly_saving"], "additionalProperties": false,
                ]],
            ],
            "required": ["headline", "tips"], "additionalProperties": false,
        ]
        do {
            var result = try await claude.structured(Advice.self, system: system, user: Self.summary(context: context), schema: schema, effort: "medium")
            result.generatedAt = .now
            advice = result
            if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: cacheKey) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Plain-text money picture: budget, three months by category, top merchants, subscriptions, bills due.
    static func summary(context: ModelContext, months: Int = 3) -> String {
        let txns = (try? context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let budget = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
        let cal = Calendar.current
        var lines = ["Currency: \(Fmt.currencyCode). Monthly budget: \(Fmt.money(budget)). Today: \(Date.now.formatted(date: .complete, time: .omitted))."]

        for back in (0..<months).reversed() {
            let start = cal.date(byAdding: .month, value: -back, to: Date.now.startOfMonth)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            let m = txns.filter { $0.date >= start && $0.date < end }
            let spent = -m.filter(\.isExpense).reduce(0) { $0 + $1.amount }
            let income = m.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
            lines.append("\n\(start.formatted(.dateTime.month(.wide).year()))\(back == 0 ? " (so far, day \(cal.component(.day, from: .now)))" : ""): spent \(Fmt.money(spent)), income \(Fmt.money(income))")
            let byCat = Dictionary(grouping: m.filter(\.isExpense), by: \.category).mapValues { -$0.reduce(0) { $0 + $1.amount } }
            for (c, v) in byCat.sorted(by: { $0.value > $1.value }) { lines.append("  \(c): \(Fmt.money(v))") }
            let byMerchant = Dictionary(grouping: m.filter(\.isExpense), by: { $0.title }).mapValues { ($0.count, -$0.reduce(0) { $0 + $1.amount }) }
            let top = byMerchant.sorted { $0.value.1 > $1.value.1 }.prefix(8)
            if !top.isEmpty {
                lines.append("  Top: " + top.map { "\($0.key) \(Fmt.money($0.value.1)) (\($0.value.0)x)" }.joined(separator: ", "))
            }
        }
        var seen = Set<String>()
        let recurring = txns.reversed().filter { $0.isRecurring && $0.isExpense && seen.insert($0.title.lowercased()).inserted }
        if !recurring.isEmpty {
            lines.append("\nRecurring / subscriptions: " + recurring.map { "\($0.title) \(Fmt.money(-$0.amount))" }.joined(separator: ", "))
        }
        let bills = tasks.filter { $0.area == .money && !$0.isDone && $0.due != nil }
        if !bills.isEmpty {
            lines.append("Bills due: " + bills.map { "\($0.title) (\(Fmt.relativeDay($0.due!)))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Dark "money coach" card on the Money screen.
struct MoneyCoachCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @ObservedObject private var coach = MoneyCoach.shared
    @ObservedObject private var ai = AIAssistant.shared

    private let ink = Color(hex: 0xF4F4F5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.lime)
                Text("Money coach").font(Theme.ui(12, weight: .semibold)).opacity(0.7)
                Spacer()
                if coach.loading { ProgressView().controlSize(.small).tint(ink) }
                if ai.hasKey {
                    Button { Task { await coach.refresh(context: context, force: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).disabled(coach.loading).help("Refresh advice")
                }
            }
            if !ai.hasKey {
                Text("Add your Anthropic API key in Settings › AI to get savings advice.").font(Theme.ui(13)).opacity(0.8)
            } else if let a = coach.advice {
                Text(a.headline).font(Theme.display(20)).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(a.tips) { tip in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(tip.title).font(Theme.ui(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 6)
                                if tip.monthly_saving > 0 {
                                    Text("~\(Fmt.money(tip.monthly_saving))/mo").font(Theme.ui(11, weight: .bold))
                                        .foregroundStyle(Theme.stickerInk)
                                        .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Theme.lime))
                                }
                            }
                            Text(tip.detail).font(Theme.ui(12)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                    }
                }
            } else if let e = coach.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12))
            } else if !coach.loading {
                Text("Add a few expenses (or connect Gmail) and \(AssistantName.current) will suggest where you can save.").font(Theme.ui(13)).opacity(0.8)
            } else {
                Text("\(AssistantName.current) is looking at your spending…").font(Theme.display(18, weight: .regular))
            }
            if ai.hasKey {
                Button {
                    state.openAssistant(with: "Let's talk about my spending. Where is my money going, and what should I change?")
                } label: {
                    Label("Discuss with \(AssistantName.current)", systemImage: "bubble.left.and.text.bubble.right.fill")
                        .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x141416)))
        .task { await coach.refresh(context: context) }
    }
}
