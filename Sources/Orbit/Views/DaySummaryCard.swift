import SwiftUI
import SwiftData

/// Today › Your day: the AI summary of where your day stands, kept up to date as things change.
struct DaySummaryCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var store = DaySummaryStore.shared
    @ObservedObject private var ai = AIAssistant.shared
    // Watching these makes the card re-check whenever any of them changes.
    @Query private var txns: [Transaction]
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [ReadingSession]
    @Query private var focus: [FocusSession]

    var compact = false

    private var changeKey: String {
        "\(txns.count)-\(tasks.filter(\.isDone).count)-\(sessions.count)-\(focus.count)-\(ai.hasKey)"
    }

    var body: some View {
        Group {
            if ai.hasKey { card }
        }
        .task(id: changeKey) {
            try? await Task.sleep(for: .seconds(2))   // let a burst of edits settle
            await store.refreshIfNeeded(context: context, apple: apple)
        }
        .task {
            // The day moves on even when nothing is edited: look again every 20 minutes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20 * 60))
                await store.refreshIfNeeded(context: context, apple: apple)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon.fill").foregroundStyle(Theme.orange)
                Text("Your day").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                else if let s = store.summary, store.isToday {
                    Text("Updated \(Fmt.time(s.generatedAt))").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                Button { Task { await store.refreshIfNeeded(context: context, apple: apple, force: true) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26).background(Circle().fill(Theme.canvas))
                }
                .buttonStyle(.plain).disabled(store.loading).help("Update now")
            }
            if let s = store.summary, store.isToday {
                Text(s.line).font(Theme.display(compact ? 18 : 19)).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(s.tiles.prefix(6), id: \.self) { tile($0) }
                }
                if !s.nudge.isEmpty {
                    Label(s.nudge, systemImage: "lightbulb.fill").font(Theme.ui(12, weight: .medium))
                        .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            } else if store.loading {
                Text("\(AssistantName.current) is looking at your day…").font(Theme.display(18, weight: .regular)).foregroundStyle(Theme.inkSecondary)
            } else if let e = store.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .animation(.easeOut(duration: 0.2), value: store.summary)
    }

    private func tile(_ t: DaySummary.Tile) -> some View {
        let (symbol, color) = Self.style(t.kind)
        return VStack(alignment: .leading, spacing: 4) {
            Label(t.title, systemImage: symbol).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.stickerInk.opacity(0.75)).lineLimit(1)
            Text(t.value).font(Theme.ui(15, weight: .bold)).foregroundStyle(Theme.stickerInk).lineLimit(1).minimumScaleFactor(0.7)
            Text(t.detail).font(Theme.ui(11)).foregroundStyle(Theme.stickerInk.opacity(0.75)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color))
    }

    static func style(_ kind: String) -> (String, Color) {
        switch kind {
        case "money": ("creditcard.fill", Theme.peach)
        case "reading": ("book.fill", Theme.purple)
        case "tasks": ("checklist", Theme.lime)
        case "calendar": ("calendar", Theme.cyan)
        case "habits": ("flame.fill", Theme.orange)
        case "focus": ("timer", Theme.mint)
        case "mood": ("face.smiling", Theme.pink)
        case "trips": ("airplane", Theme.cyan)
        case "places": ("mappin.and.ellipse", Theme.mint)
        default: ("sparkles", Theme.blush)
        }
    }
}
