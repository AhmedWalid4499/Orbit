import WidgetKit
import SwiftUI

// Orbit's desktop widgets. Built by scripts/build-widgets.sh into Orbit.app/Contents/PlugIns/OrbitWidgets.appex.
// The app writes widget.json into the shared app-group folder (WidgetBridge.swift); keep these types in step with it.

#if os(iOS)
let appGroup = "group.com.ahmedwalid.orbit"
#else
let appGroup = "Y2K55S3UA9.com.personal.orbit"
#endif

struct WidgetSnapshot: Codable {
    struct Event: Codable { let title: String; let start: Date; let end: Date; let allDay: Bool; let color: String }
    struct Task: Codable { let title: String; let area: String; let overdue: Bool; let priority: Int }
    struct Habit: Codable { let name: String; let symbol: String; let done: Bool; let streak: Int; let color: String }
    struct Dream: Codable { let title: String; let date: Date }
    struct ShelfBook: Codable { let title: String; let author: String; let reading: Bool; let progress: Double; let cover: String }
    var generatedAt: Date
    var userName: String
    var events: [Event]
    var tasks: [Task]
    var habits: [Habit]
    var moneyLeft: Double
    var budget: Double
    var currency: String
    var lookingForward: [Dream]
    var books: [ShelfBook]?
    var readThisYear: Int?

    static func load() -> WidgetSnapshot? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appending(path: "widget.json")) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Look

enum W {
    static let lime = Color(red: 0.90, green: 1.0, blue: 0.12)
    static let pink = Color(red: 0.97, green: 0.76, blue: 0.93)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
    static func color(_ hex: String) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return pink }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now, snapshot: WidgetSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.load()
        // One entry now and one at each upcoming event start, so "next up" moves along on its own.
        var dates = [Date.now]
        dates += (snap?.events ?? []).map(\.start).filter { $0 > .now }.prefix(6)
        let entries = dates.map { Entry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Today widget

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let s = entry.snapshot {
            let upcoming = s.events.filter { $0.end > entry.date }
            switch family {
            case .systemSmall: small(s, upcoming)
            case .systemLarge: large(s, upcoming)
            default: medium(s, upcoming)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("joshu").font(.system(size: 20, weight: .black, design: .rounded))
                Text("Open Joshu once to fill this widget.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(entry.date.formatted(.dateTime.day().month())).font(.system(size: 13, weight: .bold, design: .serif))
        }
    }

    private func small(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s)
            if let next = upcoming.first {
                Text(next.allDay ? "Today" : W.time(next.start)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(next.title).font(.system(size: 16, weight: .bold, design: .serif)).lineLimit(2)
            } else {
                Text("No more events").font(.system(size: 15, weight: .bold, design: .serif))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                pill("\(s.tasks.count)", "due", W.pink)
                pill("\(s.habits.filter(\.done).count)/\(s.habits.count)", "habits", W.lime)
            }
        }
    }

    private func medium(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(s)
                if upcoming.isEmpty { Text("Nothing else today").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { _, e in eventRow(e) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Due today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if s.tasks.isEmpty { Text("All clear 🎉").font(.caption) }
                ForEach(Array(s.tasks.prefix(4).enumerated()), id: \.offset) { _, t in taskRow(t) }
                Spacer(minLength: 0)
                habitsDots(s)
            }
        }
    }

    private func large(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(s)
            Text("Agenda").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if upcoming.isEmpty { Text("Nothing else today").font(.caption) }
            ForEach(Array(upcoming.prefix(4).enumerated()), id: \.offset) { _, e in eventRow(e) }
            Divider()
            Text("Due today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if s.tasks.isEmpty { Text("All clear 🎉").font(.caption) }
            ForEach(Array(s.tasks.prefix(4).enumerated()), id: \.offset) { _, t in taskRow(t) }
            Spacer(minLength: 0)
            HStack {
                habitsDots(s)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Left to spend").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(s.moneyLeft.formatted(.currency(code: s.currency).precision(.fractionLength(0)))).font(.system(size: 15, weight: .bold, design: .serif))
                }
            }
        }
    }

    private func eventRow(_ e: WidgetSnapshot.Event) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(W.color(e.color)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(e.allDay ? "All day" : "\(W.time(e.start)) – \(W.time(e.end))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func taskRow(_ t: WidgetSnapshot.Task) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle").font(.system(size: 9, weight: .semibold))
            Text(t.title).font(.system(size: 12)).lineLimit(1)
            if t.overdue { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundStyle(.red) }
        }
    }

    private func habitsDots(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(s.habits.prefix(6).enumerated()), id: \.offset) { _, h in
                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13)).foregroundStyle(h.done ? W.color(h.color) : .secondary)
            }
        }
    }

    private func pill(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.system(size: 12, weight: .bold))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(W.ink)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color))
    }
}

// MARK: - Habits widget

struct HabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let habits = entry.snapshot?.habits ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Habits").font(.system(size: 15, weight: .bold, design: .serif))
                Spacer()
                Text("\(habits.filter(\.done).count)/\(habits.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            if habits.isEmpty { Text("Add habits in Joshu.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(habits.prefix(family == .systemSmall ? 4 : 6).enumerated()), id: \.offset) { _, h in
                HStack(spacing: 8) {
                    Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(h.done ? W.color(h.color) : .secondary)
                    Text(h.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if h.streak > 1 && family != .systemSmall { Text("\(h.streak)🔥").font(.system(size: 11)) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Looking forward widget

struct CountdownWidgetView: View {
    let entry: Entry

    var body: some View {
        if let d = entry.snapshot?.lookingForward.first {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                       to: Calendar.current.startOfDay(for: d.date)).day ?? 0
            VStack(alignment: .leading, spacing: 4) {
                Text("Looking forward to").font(.system(size: 11, weight: .semibold)).foregroundStyle(W.ink.opacity(0.7))
                Spacer(minLength: 0)
                Text(days <= 0 ? "Today 🎉" : "\(days)").font(.system(size: days <= 0 ? 26 : 44, weight: .bold, design: .serif))
                if days > 0 { Text(days == 1 ? "day to go" : "days to go").font(.system(size: 11, weight: .semibold)) }
                Text(d.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }
            .foregroundStyle(W.ink)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Looking forward to").font(.system(size: 11, weight: .semibold))
                Text("Give a bucket-list dream a date in Joshu to count down to it.").font(.caption)
            }
            .foregroundStyle(W.ink)
        }
    }
}

// MARK: - Bookshelf widget

/// A cover image saved by the app next to widget.json.
func coverPlatformImage(_ name: String) -> PlatformCover? {
    guard !name.isEmpty, let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
    let path = dir.appending(path: "covers/\(name)").path
    #if os(iOS)
    return UIImage(contentsOfFile: path)
    #else
    return NSImage(contentsOfFile: path)
    #endif
}

#if os(iOS)
typealias PlatformCover = UIImage
func makeImage(_ i: UIImage) -> Image { Image(uiImage: i) }
func cgOf(_ i: UIImage) -> CGImage? { i.cgImage }
#else
typealias PlatformCover = NSImage
func makeImage(_ i: NSImage) -> Image { Image(nsImage: i) }
func cgOf(_ i: NSImage) -> CGImage? { i.cgImage(forProposedRect: nil, context: nil, hints: nil) }
#endif

enum Wood {
    static let frame = [Color(red: 0.55, green: 0.34, blue: 0.19), Color(red: 0.45, green: 0.27, blue: 0.14)]
    static let back = [Color(red: 0.82, green: 0.60, blue: 0.40), Color(red: 0.74, green: 0.52, blue: 0.33)]
    static let plankTop = Color(red: 0.86, green: 0.64, blue: 0.43)
    static let plankFront = [Color(red: 0.68, green: 0.45, blue: 0.27), Color(red: 0.56, green: 0.36, blue: 0.20)]
}

/// The back of the cabinet: warm wood with faint grain.
struct WoodPanel: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: Wood.back, startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var x: CGFloat = 0, i = 0
                while x < size.width {
                    var p = Path()
                    let wobble = CGFloat((i * 37) % 7) - 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addCurve(to: CGPoint(x: x + wobble, y: size.height), control1: CGPoint(x: x + 4, y: size.height * 0.3),
                               control2: CGPoint(x: x - 4, y: size.height * 0.7))
                    ctx.stroke(p, with: .color(.black.opacity(i % 3 == 0 ? 0.07 : 0.035)), lineWidth: i % 4 == 0 ? 1.2 : 0.6)
                    x += CGFloat(5 + (i * 13) % 9); i += 1
                }
            }
            // Shade at the top, like the shelf above casts it.
            LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
        }
    }
}

struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            Wood.plankTop.frame(height: 3)
            LinearGradient(colors: Wood.plankFront, startPoint: .top, endPoint: .bottom).frame(height: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
    }
}

/// Average colour of a cover, for its spine.
func spineColor(_ name: String) -> (Color, Bool)? {
    guard let img = coverPlatformImage(name), let cg = cgOf(img) else { return nil }
    var px = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
    // Richer than a plain average, so spines don't all come out beige.
    let mx = max(r, g, b), mn = min(r, g, b)
    let boost = mx - mn < 0.12 ? 1.0 : 1.25
    func c(_ v: Double) -> Double { min(1, max(0, mn + (v - mn) * boost)) }
    let light = 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    return (Color(red: c(r), green: c(g), blue: c(b)), light)
}

func seed(_ s: String) -> Int { abs(s.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 }) }

let fallbackSpines: [Color] = [Color(red: 0.80, green: 0.26, blue: 0.22), Color(red: 0.16, green: 0.32, blue: 0.55), Color(red: 0.20, green: 0.45, blue: 0.33),
                               Color(red: 0.93, green: 0.67, blue: 0.18), Color(red: 0.35, green: 0.22, blue: 0.45), Color(red: 0.12, green: 0.12, blue: 0.14)]

/// A book seen from the side, its title running up the spine.
struct Spine: View {
    let book: WidgetSnapshot.ShelfBook
    var height: CGFloat
    var body: some View {
        let s = seed(book.title)
        let (fill, light) = spineColor(book.cover) ?? (fallbackSpines[s % fallbackSpines.count], false)
        let h = height * (0.82 + Double(s % 18) / 100)
        let w = max(14, height * (0.17 + Double(s % 5) / 100))
        ZStack {
            LinearGradient(colors: [fill.opacity(0.85), fill, fill.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                Rectangle().fill((light ? Color.black : .white).opacity(0.35)).frame(height: 1.5).padding(.top, h * 0.07)
                Spacer()
                Rectangle().fill((light ? Color.black : .white).opacity(0.35)).frame(height: 1.5).padding(.bottom, h * 0.07)
            }
            Text(book.title.uppercased())
                .font(.system(size: max(6, w * 0.42), weight: .heavy, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(light ? Color.black.opacity(0.8) : .white)
                .frame(width: h * 0.72)
                .rotationEffect(.degrees(90))
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 0)
    }
}

/// A book standing face-out, with a reading ribbon showing progress.
struct FaceOut: View {
    let book: WidgetSnapshot.ShelfBook
    var height: CGFloat
    var body: some View {
        let w = height * 0.67
        ZStack(alignment: .bottom) {
            if let img = coverPlatformImage(book.cover) {
                makeImage(img).resizable().aspectRatio(contentMode: .fill)
            } else {
                fallbackSpines[seed(book.title) % fallbackSpines.count]
                Text(book.title).font(.system(size: max(7, w * 0.14), weight: .bold, design: .serif)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(5).frame(maxHeight: .infinity)
            }
            if book.reading {
                // Progress along the bottom edge.
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.45))
                        Rectangle().fill(Color(red: 0.90, green: 1.0, blue: 0.12)).frame(width: g.size.width * book.progress)
                    }
                }
                .frame(height: 3.5)
            }
        }
        .frame(width: w, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(alignment: .leading) { LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 3) }
        .shadow(color: .black.opacity(0.4), radius: 2, x: 2, y: 1)
    }
}

/// Little things on the shelf.
struct Plant: View {
    var size: CGFloat
    var body: some View {
        let leaf = LinearGradient(colors: [Color(red: 0.45, green: 0.78, blue: 0.38), Color(red: 0.18, green: 0.50, blue: 0.24)], startPoint: .top, endPoint: .bottom)
        VStack(spacing: -size * 0.04) {
            ZStack(alignment: .bottom) {
                ForEach([-34.0, -14, 0, 14, 34], id: \.self) { angle in
                    Ellipse().fill(leaf)
                        .frame(width: size * 0.16, height: size * (angle == 0 ? 0.6 : 0.5))
                        .rotationEffect(.degrees(angle), anchor: .bottom)
                }
            }
            .frame(width: size * 0.7, height: size * 0.6, alignment: .bottom)
            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: size * 0.1, bottomTrailingRadius: size * 0.1, topTrailingRadius: 1)
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.47, blue: 0.30), Color(red: 0.70, green: 0.35, blue: 0.22)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.42, height: size * 0.36)
        }
        .frame(width: size * 0.75)
    }
}

struct Trophy: View {
    var size: CGFloat
    var count: Int
    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Image(systemName: "trophy.fill").font(.system(size: size * 0.8)).foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 0.85, green: 0.6, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                Text("\(count)").font(.system(size: size * 0.26, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.5, green: 0.32, blue: 0.05))
                    .offset(y: -size * 0.12)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}

/// One shelf: things standing on a plank.
struct ShelfRow<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 3) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 10)
            Plank()
        }
        .frame(height: height + 9)
    }
}

struct BookshelfLayout: View {
    let family: WidgetFamily
    let books: [WidgetSnapshot.ShelfBook]
    let readCount: Int

    var body: some View {
        let reading = books.filter(\.reading), next = books.filter { !$0.reading }
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: Wood.frame, startPoint: .top, endPoint: .bottom)
                WoodPanel()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(9)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                shelves(reading: reading, next: next, size: g.size)
                    .padding(.horizontal, 9).padding(.bottom, 9).padding(.top, 9)
            }
        }
    }

    @ViewBuilder
    private func shelves(reading: [WidgetSnapshot.ShelfBook], next: [WidgetSnapshot.ShelfBook], size: CGSize) -> some View {
        switch family {
        case .systemSmall:
            let h = size.height - 18 - 9 - 12
            ShelfRow(height: h) {
                if let b = reading.first ?? books.first { FaceOut(book: b, height: h * 0.86) }
                ForEach(Array((reading.dropFirst() + next).prefix(2).enumerated()), id: \.offset) { Spine(book: $0.element, height: h * 0.86) }
                Spacer(minLength: 0)
            }
        case .systemMedium:
            let h = size.height - 18 - 9 - 12
            ShelfRow(height: h) {
                ForEach(Array(reading.prefix(2).enumerated()), id: \.offset) { FaceOut(book: $0.element, height: h * 0.9).padding(.trailing, 4) }
                ForEach(Array(next.prefix(5).enumerated()), id: \.offset) { Spine(book: $0.element, height: h * 0.9) }
                Spacer(minLength: 0)
                Plant(size: h * 0.55).padding(.trailing, 4)
            }
        default:
            let h = (size.height - 18 - 18 - 16) / 2
            VStack(spacing: 8) {
                ShelfRow(height: h) {
                    Trophy(size: h * 0.42, count: readCount).padding(.trailing, 6)
                    ForEach(Array((reading.isEmpty ? Array(books.prefix(1)) : reading).prefix(3).enumerated()), id: \.offset) {
                        FaceOut(book: $0.element, height: h * 0.92).padding(.trailing, 4)
                    }
                    Spacer(minLength: 0)
                    Plant(size: h * 0.5).padding(.trailing, 4)
                }
                ShelfRow(height: h) {
                    ForEach(Array(next.prefix(5).enumerated()), id: \.offset) { i, b in
                        if i < 2 { FaceOut(book: b, height: h * 0.86).padding(.trailing, 3) } else { Spine(book: b, height: h * 0.9) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct BookshelfWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let books = entry.snapshot?.books ?? []
        if books.isEmpty {
            ZStack {
                LinearGradient(colors: Wood.frame, startPoint: .top, endPoint: .bottom)
                WoodPanel().clipShape(RoundedRectangle(cornerRadius: 4)).padding(9)
                Text("Add books in Joshu › Reading and they'll stand here.").font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(.white).multilineTextAlignment(.center).padding(24)
            }
        } else {
            BookshelfLayout(family: family, books: books, readCount: entry.snapshot?.readThisYear ?? 0)
        }
    }
}

// MARK: - Widgets

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitToday", provider: Provider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/today"))
        }
        .configurationDisplayName("Joshu Today")
        .description("Your next events, what's due and your habits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitHabits", provider: Provider()) { entry in
            HabitsWidgetView(entry: entry).containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/habits"))
        }
        .configurationDisplayName("Joshu Habits")
        .description("Today's habits and streaks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitCountdown", provider: Provider()) { entry in
            CountdownWidgetView(entry: entry).containerBackground(W.lime, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/bucket"))
        }
        .configurationDisplayName("Looking forward to")
        .description("Counts down to the next date on your bucket list.")
        .supportedFamilies([.systemSmall])
    }
}

struct BookshelfWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitBookshelf", provider: Provider()) { entry in
            BookshelfWidgetView(entry: entry).containerBackground(for: .widget) { LinearGradient(colors: Wood.frame, startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.personal.orbit://open/reading"))
        }
        .configurationDisplayName("Bookshelf")
        .description("The books you're reading and the ones you want to read next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct OrbitWidgets: WidgetBundle {
    var body: some Widget {
        BookshelfWidget()
        TodayWidget()
        HabitsWidget()
        CountdownWidget()
    }
}
