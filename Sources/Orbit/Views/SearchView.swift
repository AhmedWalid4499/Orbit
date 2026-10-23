import SwiftUI
import SwiftData

// MARK: - Search (⌘K)

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @Query private var tasks: [TaskItem]
    @Query private var notes: [Note]
    @Query private var events: [EventItem]
    @Query private var txns: [Transaction]
    @Query private var books: [Book]
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Hit: Identifiable { let id = UUID(); let title: String; let detail: String; let symbol: String; let tab: Tab }

    private var hits: [Hit] {
        guard query.count >= 2 else { return [] }
        func m(_ s: String) -> Bool { s.localizedCaseInsensitiveContains(query) }
        var r: [Hit] = []
        r += tasks.filter { m($0.title) }.prefix(8).map {
            Hit(title: $0.title, detail: $0.isDone ? "Completed task" : "Task · \($0.area.title)", symbol: "checkmark.circle", tab: .tasks)
        }
        r += events.filter { m($0.title) }.prefix(6).map {
            Hit(title: $0.title, detail: "Event · \($0.start.formatted(date: .abbreviated, time: .shortened))", symbol: "calendar", tab: .calendar)
        }
        r += notes.filter { m($0.title) || m($0.body) }.prefix(6).map {
            Hit(title: $0.title.isEmpty ? "Untitled" : $0.title, detail: $0.isJournal ? "Journal" : "Note", symbol: "doc.text", tab: .notes)
        }
        r += txns.filter { m($0.title) }.prefix(6).map {
            Hit(title: $0.title, detail: "\(Fmt.money($0.amount, signed: true)) · \($0.date.formatted(date: .abbreviated, time: .omitted))",
                symbol: "creditcard", tab: .money)
        }
        r += books.filter { m($0.title) || m($0.author) }.prefix(6).map {
            Hit(title: $0.title, detail: "Book · \($0.author) · \($0.status.title)", symbol: "book", tab: .reading)
        }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.inkMuted)
                TextField("Search tasks, events, notes, money…", text: $query)
                    .textFieldStyle(.plain).font(Theme.ui(20)).focused($focused)
                    .onSubmit { if let first = hits.first { go(first.tab) } }
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    if query.count >= 2 && hits.isEmpty { EmptyHint(symbol: "questionmark", text: "No matches").padding() }
                    ForEach(hits) { hit in
                        Button { go(hit.tab) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: hit.symbol).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title).font(Theme.ui(14, weight: .medium))
                                    Text(hit.detail).font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(height: 360)
        }
        .frame(width: 620)
        .onAppear { focused = true }
        .onEscape { dismiss() }
    }

    private func go(_ tab: Tab) {
        state.tab = tab
        dismiss()
    }
}
