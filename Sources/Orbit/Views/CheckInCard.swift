import SwiftUI
import SwiftData

/// Today: the assistant asks you something about your day (how the meeting went, what would make today good,
/// how you're feeling tonight). Your answer opens the chat so you can keep talking.
struct CheckInCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var ai = AIAssistant.shared
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(filter: #Predicate<TaskItem> { $0.isDone }) private var done: [TaskItem]
    /// The question already answered (day + part of day), so the card steps back until the next one.
    @AppStorage("checkin.answered") private var answered = ""
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var slot: String {
        let h = Calendar.current.component(.hour, from: .now)
        return DayKey.key(.now) + (h < 12 ? "-am" : h < 17 ? "-pm" : "-eve")
    }

    private var question: (text: String, chips: [String]) {
        let now = Date.now, today = now.startOfDay, h = Calendar.current.component(.hour, from: now)
        let entries = CalEntry.merge(local: events.filter { $0.start >= today && $0.start < today.adding(days: 1) },
                                     apple: apple.events(from: today, to: today.adding(days: 1)),
                                     google: GoogleCalendarStore.shared.events(from: today, to: today.adding(days: 1)))
            .filter { !$0.isAllDay }
        let doneToday = done.filter { $0.completedAt?.isSameDay(as: now) ?? false }.count
        if h < 12 {
            if let next = entries.first(where: { $0.start > now }) {
                return ("You've got \(next.title) at \(Fmt.time(next.start)). What's the one thing you want to get done today?",
                        ["Ready for it", "Bit nervous", "Just getting through"])
            }
            return ("Morning! What would make today a good day?", ["Getting things done", "Some rest", "Seeing people"])
        }
        if h < 17 {
            if let last = entries.last(where: { $0.end < now && $0.end > now.addingTimeInterval(-5 * 3600) }) {
                return ("How did \(last.title) go?", ["Went well 🙌", "It was okay", "Not great"])
            }
            return ("How's your day going so far?", ["Pretty good", "Busy", "Dragging a bit"])
        }
        if doneToday >= 3 {
            return ("You got \(doneToday) things done today. How are you feeling about it?", ["Proud 💪", "Tired", "Could've done more"])
        }
        return ("How was today, really? Anything you want to remember?", ["Good day 🙂", "Meh", "Rough one"])
    }

    var body: some View {
        if ai.hasKey && answered != slot {
            let q = question
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AssistantAvatar(size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(AssistantName.current) asks").font(Theme.ui(11, weight: .semibold)).opacity(0.65)
                        Text(q.text).font(Theme.ui(15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { answered = slot } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .bold)).opacity(0.5).help("Not now")
                }
                FlowLayout(spacing: 6) {
                    ForEach(q.chips, id: \.self) { chip in
                        Button { answer(chip, to: q.text) } label: {
                            Text(chip).font(Theme.ui(12, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("", text: $draft, prompt: Text("Tell \(AssistantName.current)…").foregroundStyle(Theme.stickerInk.opacity(0.45)))
                        .textFieldStyle(.plain).font(Theme.ui(13)).foregroundStyle(Theme.stickerInk)
                        .focused($focused).onSubmit { answer(draft, to: q.text) }
                    MicButton { heard in answer(heard, to: q.text) }
                    Button { answer(draft, to: q.text) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.stickerInk))
                    }
                    .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.7)))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.lavender, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .foregroundStyle(Theme.stickerInk)
        }
    }

    private func answer(_ text: String, to question: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        answered = slot
        state.openAssistant(with: "(You asked me on the Today screen: “\(question)”)\n\(t)")
    }
}
