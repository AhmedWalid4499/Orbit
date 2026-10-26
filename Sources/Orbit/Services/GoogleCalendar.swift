import Foundation
import SwiftUI

struct GoogleEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    let color: Color
    let account: String
}

/// Google Calendar events for every connected Google account, using the same sign-in as Gmail.
@MainActor
final class GoogleCalendarStore: ObservableObject {
    static let shared = GoogleCalendarStore()

    @AppStorage("googleCalendarEnabled") var enabled = true
    @Published private(set) var all: [GoogleEvent] = []
    @Published private(set) var lastRefresh: Date?
    /// Accounts signed in before Calendar was added: they need to approve it once more.
    @Published private(set) var needsConsent: Set<String> = []
    @Published private(set) var apiDisabled = false
    @Published private(set) var error: String?

    static let enableAPIURL = URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")!

    func events(from start: Date, to end: Date) -> [GoogleEvent] {
        guard enabled else { return [] }
        return all.filter { $0.start < end && $0.end > start }
    }

    func refreshIfDue() async {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 15 * 60 { return }
        await refresh()
    }

    func refresh() async {
        guard enabled, !Snapshot.isActive else { return }
        let accounts = InboxStore.shared.accounts
        guard !accounts.isEmpty else { all = []; return }
        let start = Date.now.startOfDay.adding(days: -45), end = Date.now.startOfDay.adding(days: 180)
        var collected: [GoogleEvent] = []
        var consent = Set<String>()
        var disabled = false
        var problems: [String] = []

        for account in accounts {
            do {
                let token = try await GoogleAuth.accessToken(for: account)
                let list = try await calendarJSON("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader", token: token)
                let calendars = (list["items"] as? [[String: Any]] ?? []).filter { ($0["selected"] as? Bool) ?? ($0["primary"] as? Bool ?? false) }
                for cal in calendars {
                    guard let calID = cal["id"] as? String else { continue }
                    let name = cal["summaryOverride"] as? String ?? cal["summary"] as? String ?? "Google"
                    let color = Color(hexString: cal["backgroundColor"] as? String) ?? Theme.cyan
                    collected += try await fetchEvents(calendarID: calID, name: name, color: color, account: account,
                                                       token: token, from: start, to: end)
                }
            } catch let e as CalendarError {
                switch e {
                case .needsConsent: consent.insert(account)
                case .apiDisabled: disabled = true
                case .other(let m): problems.append("\(account): \(m)")
                }
            } catch {
                problems.append("\(account): \(error.localizedDescription)")
            }
        }
        all = collected
        needsConsent = consent
        apiDisabled = disabled
        error = problems.first
        lastRefresh = .now
    }

    /// Re-runs Google sign-in for an account so it also allows Calendar.
    func reconnect(_ account: String) async {
        await InboxStore.shared.addAccount(hint: account)
        lastRefresh = nil
        await refresh()
    }

    private func fetchEvents(calendarID: String, name: String, color: Color, account: String, token: String,
                             from: Date, to: Date) async throws -> [GoogleEvent] {
        var out: [GoogleEvent] = []
        var pageToken: String?
        let iso = ISO8601DateFormatter()
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX"); dayOnly.dateFormat = "yyyy-MM-dd"
        repeat {
            var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "@#"))) ?? calendarID)/events")!
            comps.queryItems = [
                .init(name: "timeMin", value: iso.string(from: from)), .init(name: "timeMax", value: iso.string(from: to)),
                .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "2500"),
            ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let json = try await calendarJSON(comps.url!.absoluteString, token: token)
            for e in json["items"] as? [[String: Any]] ?? [] {
                guard (e["status"] as? String) != "cancelled",
                      let s = e["start"] as? [String: Any], let en = e["end"] as? [String: Any] else { continue }
                let allDay = s["date"] != nil
                let start = allDay ? dayOnly.date(from: s["date"] as? String ?? "") : (s["dateTime"] as? String).flatMap(iso.date)
                let end = allDay ? dayOnly.date(from: en["date"] as? String ?? "") : (en["dateTime"] as? String).flatMap(iso.date)
                guard let start, let end else { continue }
                out.append(GoogleEvent(id: "\(account)-\(e["id"] as? String ?? UUID().uuidString)", title: e["summary"] as? String ?? "(No title)",
                                       start: start, end: end, isAllDay: allDay, calendarName: name, color: color, account: account))
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return out
    }

    private enum CalendarError: Error { case needsConsent, apiDisabled, other(String) }

    private func calendarJSON(_ url: String, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        let body = String(data: data, encoding: .utf8) ?? ""
        if status == 403 && (body.contains("accessNotConfigured") || body.contains("SERVICE_DISABLED")) { throw CalendarError.apiDisabled }
        if status == 403 && (body.contains("insufficient") || body.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT")) { throw CalendarError.needsConsent }
        throw CalendarError.other("Google Calendar returned an error (\(status)).")
    }
}

extension Color {
    /// "#9fe1e7" → Color
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// Shown in Calendar when Google needs one more click before events can appear.
struct GoogleCalendarBanner: View {
    @ObservedObject private var store = GoogleCalendarStore.shared

    var body: some View {
        if store.apiDisabled {
            banner("Turn on Google Calendar for your Joshu project (one click), then come back.",
                   action: "Enable Calendar API") { Platform.open(GoogleCalendarStore.enableAPIURL) }
        } else if let account = store.needsConsent.sorted().first {
            banner("Allow Joshu to read the calendar of \(account). You'll approve it once in your browser.",
                   action: "Connect Google Calendar") { Task { await store.reconnect(account) } }
        }
    }

    private func banner(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.cyan)
            Text(text).font(Theme.ui(13))
            Spacer()
            Button(action, action: perform).buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}
