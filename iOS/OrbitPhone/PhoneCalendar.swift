import SwiftUI
import SwiftData

/// Calendar on iPhone: a week strip or month grid on top, the chosen day's events below.
struct PhoneCalendar: View {
    @EnvironmentObject private var apple: AppleSync
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]

    @State private var day = Date.now.startOfDay
    @State private var showMonth = false
    @State private var adding = false
    @State private var detail: CalEntry?

    private let cal = Calendar.current

    private func entries(from: Date, to: Date) -> [CalEntry] {
        _ = apple.revision
        return CalEntry.merge(local: events.filter { $0.start >= from && $0.start < to }, apple: apple.events(from: from, to: to),
                              google: GoogleCalendarStore.shared.events(from: from, to: to))
    }

    private var week: [Date] { (0..<7).map { day.startOfWeek.adding(days: $0) } }
    private var monthDays: [Date] {
        let first = day.startOfMonth.startOfWeek
        return (0..<42).map { first.adding(days: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(day.formatted(.dateTime.month(.wide).year())).font(Theme.display(22))
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain).font(.system(size: 16, weight: .semibold))

                Picker("", selection: $showMonth) { Text("Week").tag(false); Text("Month").tag(true) }.pickerStyle(.segmented)

                if showMonth { month } else { weekStrip }

                HStack {
                    Text(day.isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month())).font(Theme.display(22))
                    Spacer()
                    if !day.isToday { Button("Today") { withAnimation { day = .now.startOfDay } }.buttonStyle(SoftButtonStyle()) }
                    Button { adding = true } label: { Label("Event", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
                }
                let list = entries(from: day, to: day.adding(days: 1))
                if list.isEmpty { EmptyHint(symbol: "calendar", text: apple.calendarEnabled ? "Nothing on this day." : "Nothing here yet. Connect Apple Calendar in Settings to see all your calendars.") }
                ForEach(list) { e in
                    AgendaRow(entry: e).onTapGesture { detail = e }
                }
                let due = open.filter { $0.due.map { $0.isSameDay(as: day) } ?? false }
                if !due.isEmpty {
                    Text("Tasks due").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.inkSecondary).padding(.top, 6)
                    ForEach(due) { TaskRow(task: $0, showDue: false) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > abs(v.translation.height) { move(v.translation.width < 0 ? 1 : -1) }
        })
        .sheet(isPresented: $adding) { NewEventPopover(start: defaultStart) { adding = false }.presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { e in EventDetailPopover(entry: e) { detail = nil }.presentationDetents([.medium]) }
        .phoneChrome("Calendar")
    }

    private var defaultStart: Date {
        let hour = day.isToday ? min(cal.component(.hour, from: .now) + 1, 22) : 9
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func move(_ step: Int) {
        withAnimation(.snappy) {
            day = showMonth ? cal.date(byAdding: .month, value: step, to: day)!.startOfMonth : day.adding(days: 7 * step)
        }
    }

    private var weekStrip: some View {
        let counts = Dictionary(grouping: entries(from: week[0], to: week[6].adding(days: 1)), by: { $0.start.startOfDay }).mapValues(\.count)
        return HStack(spacing: 6) {
            ForEach(week, id: \.self) { d in
                let selected = d.isSameDay(as: day)
                Button { withAnimation(.snappy) { day = d } } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(Theme.ui(11, weight: .semibold)).opacity(0.7)
                        Text(d.formatted(.dateTime.day())).font(Theme.display(18, weight: d.isToday ? .bold : .medium))
                        Circle().fill(selected ? Theme.stickerInk : Theme.ink).frame(width: 5, height: 5).opacity((counts[d] ?? 0) > 0 ? 1 : 0)
                    }
                    .foregroundStyle(selected ? Theme.stickerInk : Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.lime : (d.isToday ? Theme.card : .clear)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var month: some View {
        let all = entries(from: monthDays[0], to: monthDays[41].adding(days: 1))
        let counts = Dictionary(grouping: all, by: { $0.start.startOfDay }).mapValues(\.count)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(monthDays.prefix(7), id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(monthDays, id: \.self) { d in
                    let selected = d.isSameDay(as: day)
                    let inMonth = cal.isDate(d, equalTo: day, toGranularity: .month)
                    Button { withAnimation(.snappy) { day = d } } label: {
                        VStack(spacing: 3) {
                            Text(d.formatted(.dateTime.day())).font(Theme.ui(15, weight: d.isToday ? .bold : .regular))
                            HStack(spacing: 2) {
                                ForEach(0..<min(counts[d] ?? 0, 3), id: \.self) { _ in Circle().frame(width: 4, height: 4) }
                            }
                            .frame(height: 4)
                        }
                        .foregroundStyle(selected ? Theme.stickerInk : Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.lime : (d.isToday ? Theme.card : .clear)))
                        .opacity(inMonth ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
