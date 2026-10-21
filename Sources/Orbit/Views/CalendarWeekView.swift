import SwiftUI
import SwiftData

struct CalendarWeekView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @Query(sort: \EventItem.start) private var events: [EventItem]

    enum Mode: String, CaseIterable { case day, week, month }
    @AppStorage("calendarMode") private var mode: Mode = .week
    /// The date being looked at; the visible day, week or month is derived from it.
    @State private var anchor = Date.now
    @State private var newSlot: Date?
    @State private var selected: CalEntry?

    private let hours = Array(6...23)
    private let hourHeight: CGFloat = 76
    private let gutter: CGFloat = 64

    private var weekStart: Date { mode == .day ? anchor.startOfDay : anchor.startOfWeek }
    private var days: [Date] { mode == .day ? [anchor.startOfDay] : (0..<7).map { weekStart.adding(days: $0) } }
    /// Six full weeks covering the anchor's month.
    private var monthDays: [Date] { (0..<42).map { anchor.startOfMonth.startOfWeek.adding(days: $0) } }

    private var range: (start: Date, end: Date) {
        switch mode {
        case .day: (anchor.startOfDay, anchor.startOfDay.adding(days: 1))
        case .week: (weekStart, weekStart.adding(days: 7))
        case .month: (monthDays.first!, monthDays.last!.adding(days: 1))
        }
    }

    private var entries: [CalEntry] {
        _ = apple.revision
        let (start, end) = range
        let local = events.filter { $0.start < end && $0.end > start }
        return CalEntry.merge(local: local, apple: apple.events(from: start, to: end))
    }

    private func step(_ direction: Int) {
        let cal = Calendar.current
        withAnimation {
            switch mode {
            case .day: anchor = anchor.adding(days: direction)
            case .week: anchor = anchor.adding(days: 7 * direction)
            case .month: anchor = cal.date(byAdding: .month, value: direction, to: anchor)!
            }
        }
    }

    private var title: String {
        switch mode {
        case .day: anchor.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .week: weekStart.adding(days: 3).formatted(.dateTime.month(.abbreviated).year())
        case .month: anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal, 32).padding(.bottom, 8).fixedSize(horizontal: false, vertical: true)
            if mode == .month {
                MonthGrid(days: monthDays, month: anchor, entries: entries) { day in
                    anchor = day
                    withAnimation { mode = .day }
                }
                .padding(.horizontal, 32).padding(.bottom, 22)
            } else {
                Divider().overlay(Theme.line).padding(.leading, 32 + gutter).padding(.trailing, 32)
                dayHeader.padding(.horizontal, 32).fixedSize(horizontal: false, vertical: true)
                allDayRow.padding(.horizontal, 32).fixedSize(horizontal: false, vertical: true)
                ScrollViewReader { proxy in
                    ScrollView {
                        grid.padding(.horizontal, 32).padding(.top, 10).padding(.bottom, 24)
                    }
                    .scrollIndicators(.never)
                    .onAppear { proxy.scrollTo(7, anchor: .top) }
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(-3...3, id: \.self) { m in
                    let date = Calendar.current.date(byAdding: .month, value: m, to: anchor)!
                    Button(date.formatted(.dateTime.month(.wide).year())) { anchor = date.startOfMonth }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(Theme.display(36))
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            HStack(spacing: 2) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button(m.rawValue.capitalized) { withAnimation(.snappy) { mode = m } }
                        .buttonStyle(.plain)
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(mode == m ? Theme.onInverse : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(mode == m ? Theme.inverse : .clear))
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.card))

            if !apple.calendarEnabled {
                Button {
                    Task { await apple.connectCalendar() }
                } label: {
                    Label("Connect Apple Calendar", systemImage: "link")
                }
                .buttonStyle(SoftButtonStyle())
            }
            Button("Today") { withAnimation { anchor = .now } }
                .buttonStyle(SoftButtonStyle())
            CircleIconButton(symbol: "arrow.left", filled: true, size: 46) { step(-1) }
            CircleIconButton(symbol: "arrow.right", filled: true, size: 46) { step(1) }
        }
    }

    // MARK: Header

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.day()))
                        .font(Theme.display(40, weight: .medium))
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(day.isToday ? Theme.lime : .clear))
                        .foregroundStyle(day.isToday ? Theme.stickerInk : Theme.ink)
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.inkSecondary)
                    Rectangle().fill(Theme.inkSecondary).frame(width: 1, height: 16).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private var allDayRow: some View {
        let allDay = entries.filter(\.isAllDay)
        if !allDay.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).frame(width: gutter, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 3) {
                        ForEach(allDay.filter { $0.start <= day && $0.end > day }) { e in
                            Text(e.title).font(Theme.ui(11, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(e.tint.opacity(0.25)))
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: Grid

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    Text(hourLabel(h))
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: gutter, height: hourHeight, alignment: .topLeading)
                        .offset(y: -8)
                        .id(h)
                }
            }
            ForEach(days, id: \.self) { day in
                dayColumn(day)
            }
        }
        .overlay(alignment: .topLeading) {
            // Hour lines
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { _ in
                    Rectangle().fill(Theme.line).frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.leading, gutter)
            .frame(height: hourHeight * CGFloat(hours.count))
            .allowsHitTesting(false)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayEntries = entries.filter { !$0.isAllDay && $0.start.isSameDay(as: day) }
        let lanes = Self.lanes(for: dayEntries)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(hours, id: \.self) { h in
                        let slot = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: day)!
                        SlotCell(isPast: slot.adding(minutes: 60) < .now,
                                 isSelected: newSlot == slot) { newSlot = slot }
                            .frame(height: hourHeight)
                            .popover(isPresented: Binding(get: { newSlot == slot }, set: { if !$0 { newSlot = nil } }),
                                     arrowEdge: .trailing) {
                                NewEventPopover(start: slot) { newSlot = nil }
                            }
                    }
                }
                ForEach(dayEntries) { entry in
                    let (lane, count) = lanes[entry.id] ?? (0, 1)
                    let width = (geo.size.width - 8) / CGFloat(count)
                    EventCard(entry: entry, height: height(of: entry))
                        .frame(width: width - 4, height: height(of: entry))
                        .offset(x: 4 + CGFloat(lane) * width, y: y(of: entry.start) + 2)
                        .onTapGesture { selected = entry }
                        .popover(isPresented: Binding(get: { selected == entry }, set: { if !$0 { selected = nil } }),
                                 arrowEdge: .trailing) {
                            EventDetailPopover(entry: entry) { selected = nil }
                        }
                }
                if day.isToday { nowLine(width: geo.size.width) }
            }
        }
        .frame(height: hourHeight * CGFloat(hours.count))
        .frame(maxWidth: .infinity)
    }

    private func nowLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.critical).frame(width: 9, height: 9)
            Rectangle().fill(Theme.critical).frame(height: 2)
        }
        .frame(width: width)
        .offset(x: -4, y: y(of: .now) - 4)
        .allowsHitTesting(false)
    }

    private func y(of date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat((c.hour ?? 0) - hours.first!) * 60 + CGFloat(c.minute ?? 0)
        return max(0, minutes / 60 * hourHeight)
    }

    private func height(of e: CalEntry) -> CGFloat {
        max(28, CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hourHeight - 4)
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 12 { return "Noon" }
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)!
        return d.formatted(.dateTime.hour())
    }

    /// Assigns overlapping events side-by-side lanes.
    static func lanes(for entries: [CalEntry]) -> [String: (Int, Int)] {
        var result: [String: (Int, Int)] = [:]
        var cluster: [CalEntry] = []
        var clusterEnd = Date.distantPast
        var laneEnds: [Date] = []

        func flush() {
            let count = max(laneEnds.count, 1)
            for e in cluster { result[e.id] = (result[e.id]?.0 ?? 0, count) }
            cluster.removeAll(); laneEnds.removeAll()
        }

        for e in entries.sorted(by: { $0.start < $1.start }) {
            if e.start >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= e.start }) {
                laneEnds[free] = e.end
                result[e.id] = (free, 1)
            } else {
                laneEnds.append(e.end)
                result[e.id] = (laneEnds.count - 1, 1)
            }
            cluster.append(e)
            clusterEnd = max(clusterEnd, e.end)
        }
        flush()
        return result
    }
}

private struct SlotCell: View {
    let isPast: Bool
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            if isPast { Hatch().opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 14)).padding(4) }
            if hovering || isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.dashed.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .overlay(Image(systemName: "plus.circle").font(.system(size: 20, weight: .light)))
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }
}

private struct EventCard: View {
    let entry: CalEntry
    let height: CGFloat
    @State private var hovering = false

    private var isApple: Bool { if case .apple = entry.source { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(Theme.ui(14, weight: .medium))
                .lineLimit(height > 60 ? 2 : 1)
            if height > 56 {
                Text("\(Fmt.time(entry.start)) – \(Fmt.time(entry.end))")
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            if height > 92 {
                if let area = entry.area { AreaPill(area: area, compact: true) }
                else if case .apple(let cal) = entry.source {
                    Text(cal).font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, height > 40 ? 10 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isApple ? entry.tint.opacity(0.16) : (hovering ? Theme.cardHover : Theme.card))
        )
        .overlay(alignment: .leading) {
            if isApple {
                RoundedRectangle(cornerRadius: 2).fill(entry.tint).frame(width: 3).padding(.vertical, 8).padding(.leading, 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.canvas, lineWidth: 1.5))
        .onHover { hovering = $0 }
        .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 8, y: 4)
    }
}

// MARK: - Popovers

struct NewEventPopover: View {
    @Environment(\.modelContext) private var context
    let start: Date
    let onDone: () -> Void

    @State private var title = ""
    @State private var from: Date
    @State private var to: Date
    @State private var area: Area = .personal

    init(start: Date, onDone: @escaping () -> Void) {
        self.start = start
        self.onDone = onDone
        _from = State(initialValue: start)
        _to = State(initialValue: start.adding(minutes: 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("New event", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.ui(20, weight: .medium))
                .onSubmit(add)
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(Theme.inkSecondary)
                DatePicker("", selection: $from, displayedComponents: .date).labelsHidden()
            }
            HStack(spacing: 10) {
                Image(systemName: "clock").foregroundStyle(Theme.inkSecondary)
                DatePicker("", selection: $from, displayedComponents: .hourAndMinute).labelsHidden()
                Text("–").foregroundStyle(Theme.inkMuted)
                DatePicker("", selection: $to, displayedComponents: .hourAndMinute).labelsHidden()
            }
            AreaPicker(selection: $area)
            Button("Add", action: add)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .frame(width: 320)
        .onChange(of: from) { old, new in to = new.addingTimeInterval(to.timeIntervalSince(old)) }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let end = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: to),
                                        minute: Calendar.current.component(.minute, from: to), second: 0, of: from) ?? to
        context.insert(EventItem(title: t, start: from, end: max(end, from.adding(minutes: 15)), area: area))
        onDone()
    }
}

private struct EventDetailPopover: View {
    @Environment(\.modelContext) private var context
    let entry: CalEntry
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.title).font(Theme.display(22))
            Label(entry.start.formatted(.dateTime.weekday(.wide).day().month()), systemImage: "calendar")
            Label(entry.isAllDay ? "All day" : "\(Fmt.time(entry.start)) – \(Fmt.time(entry.end))", systemImage: "clock")
            switch entry.source {
            case .apple(let cal):
                Label("From \(cal) (Apple Calendar)", systemImage: "applelogo").foregroundStyle(Theme.inkSecondary)
            case .local(let id):
                if let event = context.model(for: id) as? EventItem {
                    AreaPicker(selection: Binding(get: { event.area }, set: { event.area = $0 }))
                    Button("Delete event", role: .destructive) {
                        context.delete(event)
                        onDone()
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
        .font(Theme.ui(13))
        .padding(20)
        .frame(width: 300, alignment: .leading)
    }
}

struct AreaPicker: View {
    @Binding var selection: Area

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Area.allCases) { area in
                AreaPill(area: area, compact: true, selected: selection == area)
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: selection == area ? 1.5 : 0))
                    .onTapGesture { selection = area }
            }
        }
    }
}

/// Simple wrapping layout for pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Month view

private struct MonthGrid: View {
    let days: [Date]
    let month: Date
    let entries: [CalEntry]
    let onOpenDay: (Date) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(days.prefix(7), id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geo in
                let rowHeight = (geo.size.height - 5 * 6) / 6
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(days[(row * 7)..<(row * 7 + 7)], id: \.self) { day in
                                MonthCell(day: day, inMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                                          entries: entries.filter { $0.start.isSameDay(as: day) || ($0.isAllDay && $0.start <= day && $0.end > day) },
                                          height: rowHeight)
                                    .onTapGesture { onOpenDay(day) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MonthCell: View {
    let day: Date
    let inMonth: Bool
    let entries: [CalEntry]
    let height: CGFloat
    @State private var hovering = false

    var body: some View {
        let fit = max(0, Int((height - 34) / 20))
        VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(Theme.display(16, weight: day.isToday ? .bold : .medium))
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Capsule().fill(day.isToday ? Theme.lime : .clear))
                .foregroundStyle(day.isToday ? Theme.stickerInk : Theme.ink)
            ForEach(entries.prefix(fit)) { e in
                HStack(spacing: 4) {
                    Circle().fill(e.tint).frame(width: 6, height: 6)
                    Text(e.isAllDay ? e.title : "\(Fmt.time(e.start)) \(e.title)").lineLimit(1)
                }
                .font(Theme.ui(10, weight: .medium))
            }
            if entries.count > fit {
                Text("+\(entries.count - fit) more").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.cardHover : Theme.card))
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Open \(day.formatted(date: .complete, time: .omitted))")
    }
}
