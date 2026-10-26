import Foundation
import SwiftUI
import Charts

/// Your YouTube channel: subscribers, views and videos, how they're moving, and how your latest videos are doing.
/// Signs in with Google (read-only YouTube access); the refresh token lives in the Keychain item like everything else.
@MainActor
final class YouTubeStore: ObservableObject {
    static let shared = YouTubeStore()

    struct Channel: Codable, Equatable {
        var id: String
        var title: String
        var handle: String
        var thumbnail: String
        var subscribers: Int
        var views: Int
        var videos: Int
        var hiddenSubscribers: Bool
    }

    struct Video: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var published: Date
        var thumbnail: String
        var views: Int
        var likes: Int
        var comments: Int
    }

    @Published private(set) var channel: Channel?
    @Published private(set) var videos: [Video] = []
    @Published private(set) var loading = false
    @Published var error: String?
    /// Subscriber count per day (yyyy-MM-dd), so Orbit can show growth over time.
    @Published private(set) var history: [String: Int] = [:]

    static let scope = "https://www.googleapis.com/auth/youtube.readonly"
    private let refreshKey = "youtube-refresh"
    private var access: (token: String, expires: Date)?

    var isConnected: Bool { Keychain.read(refreshKey) != nil }

    private init() {
        let d = UserDefaults.standard
        channel = d.data(forKey: "youtube.channel").flatMap { try? JSONDecoder().decode(Channel.self, from: $0) }
        videos = d.data(forKey: "youtube.videos").flatMap { try? JSONDecoder().decode([Video].self, from: $0) } ?? []
        history = d.dictionary(forKey: "youtube.history") as? [String: Int] ?? [:]
    }

    /// The channel in a few lines for the assistant ("how is my channel doing?"): totals, growth and recent videos.
    func summary() -> String {
        guard isConnected, let c = channel else { return "" }
        var lines = ["YouTube channel \(c.title)\(c.handle.isEmpty ? "" : " (\(c.handle))"): \(c.hiddenSubscribers ? "subscriber count hidden" : "\(c.subscribers) subscribers"), \(c.views) total views, \(c.videos) videos."]
        let days = history.keys.sorted()
        if let last = days.last, let now = history[last] {
            for (label, back) in [("7 days", 7), ("30 days", 30)] {
                let cutoff = DayKey.key(Date.now.adding(days: -back))
                if let past = days.last(where: { $0 <= cutoff }).flatMap({ history[$0] }) {
                    lines.append("Subscribers over the last \(label): \(now - past >= 0 ? "+" : "")\(now - past).")
                }
            }
        }
        for v in videos.prefix(8) {
            lines.append("- “\(v.title)” (\(v.published.formatted(date: .abbreviated, time: .omitted))): \(v.views) views, \(v.likes) likes, \(v.comments) comments")
        }
        return lines.joined(separator: "\n")
    }

    func connect() async {
        error = nil
        do {
            let t = try await GoogleAuth.authorize(scope: Self.scope)
            Keychain.write(t.refresh, account: refreshKey)
            access = (t.access, .now.addingTimeInterval(Double(t.expiresIn) - 60))
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete(refreshKey)
        access = nil
        channel = nil
        videos = []
        history = [:]
        for k in ["youtube.channel", "youtube.videos", "youtube.history", "youtube.lastRefresh"] { UserDefaults.standard.removeObject(forKey: k) }
    }

    func refreshIfDue() async {
        guard isConnected, !Snapshot.isActive else { return }
        if Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: "youtube.lastRefresh") > 3 * 3600 { await refresh() }
    }

    func refresh() async {
        guard !loading, let refresh = Keychain.read(refreshKey) else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if access == nil || access!.expires < .now {
                let t = try await GoogleAuth.refreshAccess(refresh)
                access = (t.token, .now.addingTimeInterval(Double(t.expiresIn) - 60))
            }
            let token = access!.token
            let ch = try await get("channels?part=snippet,statistics,contentDetails&mine=true", token: token)
            guard let item = (ch["items"] as? [[String: Any]])?.first else {
                throw GmailError("This Google account has no YouTube channel. Connect the account that owns your channel.")
            }
            let snippet = item["snippet"] as? [String: Any] ?? [:]
            let stats = item["statistics"] as? [String: Any] ?? [:]
            func n(_ v: Any?) -> Int { Int(v as? String ?? "") ?? (v as? Int ?? 0) }
            let c = Channel(id: item["id"] as? String ?? "", title: snippet["title"] as? String ?? "",
                            handle: snippet["customUrl"] as? String ?? "",
                            thumbnail: ((snippet["thumbnails"] as? [String: Any])?["medium"] as? [String: Any])?["url"] as? String ?? "",
                            subscribers: n(stats["subscriberCount"]), views: n(stats["viewCount"]), videos: n(stats["videoCount"]),
                            hiddenSubscribers: stats["hiddenSubscriberCount"] as? Bool ?? false)
            channel = c
            history[DayKey.key(.now)] = c.subscribers
            history = history.filter { $0.key >= DayKey.key(.now.adding(days: -400)) }

            // Latest uploads and how each is doing.
            if let uploads = ((item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any])?["uploads"] as? String {
                let list = try await get("playlistItems?part=contentDetails&maxResults=12&playlistId=\(uploads)", token: token)
                let ids = (list["items"] as? [[String: Any]] ?? []).compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
                if !ids.isEmpty {
                    let v = try await get("videos?part=snippet,statistics&id=\(ids.joined(separator: ","))", token: token)
                    let iso = ISO8601DateFormatter()
                    videos = (v["items"] as? [[String: Any]] ?? []).map { x in
                        let sn = x["snippet"] as? [String: Any] ?? [:], st = x["statistics"] as? [String: Any] ?? [:]
                        return Video(id: x["id"] as? String ?? "", title: sn["title"] as? String ?? "",
                                     published: iso.date(from: sn["publishedAt"] as? String ?? "") ?? .now,
                                     thumbnail: ((sn["thumbnails"] as? [String: Any])?["medium"] as? [String: Any])?["url"] as? String ?? "",
                                     views: n(st["viewCount"]), likes: n(st["likeCount"]), comments: n(st["commentCount"]))
                    }.sorted { $0.published > $1.published }
                }
            }
            let d = UserDefaults.standard
            d.set(try? JSONEncoder().encode(c), forKey: "youtube.channel")
            d.set(try? JSONEncoder().encode(videos), forKey: "youtube.videos")
            d.set(history, forKey: "youtube.history")
            d.set(Date.now.timeIntervalSince1970, forKey: "youtube.lastRefresh")
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Subscribers gained since `days` ago (from Orbit's own daily record), or nil before there's history.
    func gained(days: Int) -> Int? {
        guard let now = channel?.subscribers else { return nil }
        let cutoff = DayKey.key(.now.adding(days: -days))
        guard let then = history.filter({ $0.key <= cutoff }).max(by: { $0.key < $1.key })?.value else { return nil }
        return now - then
    }

    private func get(_ path: String, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3/\(path)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "YouTube didn't answer."
            if msg.lowercased().contains("has not been used") || msg.lowercased().contains("disabled") {
                throw GmailError("Turn on “YouTube Data API v3” in your Google Cloud project (APIs & Services › Library), then try again.")
            }
            throw GmailError(msg)
        }
        return json
    }

    static func short(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 10_000...: "\(n / 1000)K"
        case 1_000...: String(format: "%.1fK", Double(n) / 1000).replacingOccurrences(of: ".0K", with: "K")
        default: "\(n)"
        }
    }
}

/// Insights › YouTube: the channel at a glance, subscriber growth and the latest videos.
struct YouTubeCard: View {
    @ObservedObject private var yt = YouTubeStore.shared
    /// How many of the latest videos to list.
    var videoCount = 5

    private struct Point: Identifiable { let id: String; let day: Date; let subs: Int }
    private var points: [Point] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return yt.history.compactMap { k, v in f.date(from: k).map { Point(id: k, day: $0, subs: v) } }.sorted { $0.day < $1.day }.suffix(90).map { $0 }
    }

    var body: some View {
        if yt.isConnected {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: yt.channel?.thumbnail ?? "")) { img in img.resizable().scaledToFill() } placeholder: { Color.red.opacity(0.85) }
                        .frame(width: 44, height: 44).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(yt.channel?.title ?? "YouTube").font(Theme.display(20)).lineLimit(1)
                        Text(yt.channel?.handle ?? "Your channel").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    if yt.loading { ProgressView().controlSize(.small) }
                    Button { Task { await yt.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).disabled(yt.loading)
                }
                if let e = yt.error { Text(e).font(Theme.ui(12)).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true) }
                if let c = yt.channel {
                    HStack(spacing: 10) {
                        stat(c.hiddenSubscribers ? "Hidden" : YouTubeStore.short(c.subscribers), "Subscribers",
                             yt.gained(days: 7).map { "\($0 >= 0 ? "+" : "")\($0) this week" }, Theme.pink)
                        stat(YouTubeStore.short(c.views), "Views", nil, Theme.cyan)
                        stat("\(c.videos)", "Videos", nil, Theme.lime)
                    }
                    if points.count >= 2 {
                        Chart(points) { p in
                            LineMark(x: .value("Day", p.day), y: .value("Subscribers", p.subs)).foregroundStyle(Color.red).interpolationMethod(.monotone)
                            AreaMark(x: .value("Day", p.day), y: .value("Subscribers", p.subs))
                                .foregroundStyle(LinearGradient(colors: [Color.red.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 120)
                    } else {
                        Text("Subscriber growth fills in as Joshu checks your channel each day.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                    }
                    if !yt.videos.isEmpty {
                        Text("Latest videos").font(Theme.ui(14, weight: .semibold))
                        ForEach(yt.videos.prefix(videoCount)) { v in
                            Button { Platform.open(URL(string: "https://youtu.be/\(v.id)")!) } label: {
                                HStack(spacing: 10) {
                                    AsyncImage(url: URL(string: v.thumbnail)) { img in img.resizable().scaledToFill() } placeholder: { Theme.card }
                                        .frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(v.title).font(Theme.ui(13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text("\(YouTubeStore.short(v.views)) views · \(YouTubeStore.short(v.likes)) likes · \(v.comments) comments · \(v.published.formatted(.relative(presentation: .named)))")
                                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .task { await yt.refreshIfDue() }
        }
    }

    private func stat(_ value: String, _ label: String, _ change: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.ui(11, weight: .semibold)).opacity(0.75)
            if let change { Text(change).font(Theme.ui(10, weight: .semibold)).opacity(0.75) }
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(color))
    }
}

/// Connections row for YouTube (Mac and iPhone settings).
struct YouTubeConnectionRow: View {
    @ObservedObject private var yt = YouTubeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                BrandLogo(brand: .youtube, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(yt.channel?.title ?? "YouTube").font(.headline)
                    Text(yt.isConnected ? "Subscribers, views and your latest videos, on the YouTube tab." : "See your channel's subscribers, views and latest videos on the YouTube tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if yt.isConnected {
                    Button("Disconnect") { yt.disconnect() }
                } else {
                    Button(yt.loading ? "Connecting…" : "Connect") { Task { await yt.connect() } }.buttonStyle(.borderedProminent).disabled(yt.loading)
                }
            }
            if let e = yt.error { Text(e).font(.caption).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// The YouTube tab: your channel at a glance, or a button to connect it.
struct YouTubeView: View {
    @ObservedObject private var yt = YouTubeStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !Platform.isPhone {
                    HStack(spacing: 12) {
                        BrandLogo(brand: .youtube, size: 34)
                        Text("YouTube").font(Theme.display(38))
                    }
                }
                if yt.isConnected {
                    YouTubeCard(videoCount: 25)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        BrandLogo(brand: .youtube, size: 56)
                        Text("Your channel, in Joshu").font(Theme.display(26))
                        Text("Connect your YouTube channel to see subscribers, views and how your latest videos are doing, with growth over time. Joshu only reads; it never posts.")
                            .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        if let e = yt.error { Text(e).font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                        Button { Task { await yt.connect() } } label: {
                            Label(yt.loading ? "Connecting…" : "Connect YouTube", systemImage: "link")
                        }
                        .buttonStyle(PrimaryButtonStyle()).fixedSize().disabled(yt.loading)
                    }
                    .padding(28)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }
}
