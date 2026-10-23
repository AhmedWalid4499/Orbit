import Foundation
import CoreLocation
import MapKit
import SwiftData
import UserNotifications

/// Home and Work, saved once in Settings so "remind me when I get home" just works. Synced between devices.
enum SavedPlaces {
    struct Place: Codable, Equatable {
        var name: String
        var address: String
        var lat: Double
        var lon: Double
    }

    static func load(_ key: String) -> Place? {
        guard let s = UserDefaults.standard.string(forKey: "places.\(key)"), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: d)
    }

    static func set(_ key: String, _ place: Place?) {
        if let place, let d = try? JSONEncoder().encode(place), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "places.\(key)")
        } else {
            UserDefaults.standard.removeObject(forKey: "places.\(key)")
        }
    }

    static var home: Place? { load("home") }
    static var work: Place? { load("work") }
}

/// Reminders at a time or a place. Time reminders work everywhere; place reminders fire on iPhone
/// (iOS watches the place for you, even when Orbit is closed). Your location never leaves the phone.
@MainActor
enum SmartReminders {
    struct Resolved { let name: String; let lat: Double; let lon: Double }

    /// "home", "work", a maps link, or a place or shop name (the nearest one to you).
    static func resolve(_ text: String) async -> Resolved? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if ["home", "my home", "my house", "house", "البيت"].contains(lower) {
            return SavedPlaces.home.map { .init(name: "Home", lat: $0.lat, lon: $0.lon) }
        }
        if ["work", "the office", "office", "my office", "my work", "الشغل"].contains(lower) {
            return SavedPlaces.work.map { .init(name: "Work", lat: $0.lat, lon: $0.lon) }
        }
        if PlaceLookup.firstURL(in: t) == nil, case .here(let me) = await NearbyFinder.shared.locate() {
            // A shop or chain ("Carrefour", "a pharmacy"): the closest branch.
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = t
            request.region = MKCoordinateRegion(center: me.coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000)
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            func far(_ i: MKMapItem) -> Double {
                me.distance(from: CLLocation(latitude: i.placemark.coordinate.latitude, longitude: i.placemark.coordinate.longitude))
            }
            if let best = items.min(by: { far($0) < far($1) }) {
                let c = best.placemark.coordinate
                return .init(name: best.name ?? t, lat: c.latitude, lon: c.longitude)
            }
        }
        guard let f = await PlaceLookup.resolve(t), let c = f.coordinate else { return nil }
        return .init(name: f.name, lat: c.latitude, lon: c.longitude)
    }

    /// Notification requests for timed and place reminders (Reminders adds them with everything else).
    static func requests(tasks: [TaskItem], prefix: String) -> (timed: [UNNotificationRequest], places: [UNNotificationRequest]) {
        let now = Date.now
        var timed: [UNNotificationRequest] = []
        for t in tasks where !t.isDone {
            guard let when = t.remindAt, when > now, when < now.adding(days: 30) else { continue }
            let c = content(t, body: t.notes.isEmpty ? (t.due.map { "Due \(Fmt.relativeDay($0))" } ?? "Reminder") : t.notes)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            timed.append(UNNotificationRequest(identifier: prefix + "at-" + key(t), content: c,
                                               trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        var places: [UNNotificationRequest] = []
        #if os(iOS)
        // iOS watches up to 20 places for an app; keep the most recent ones.
        for t in tasks.filter({ !$0.isDone && $0.hasPlaceReminder }).sorted(by: { $0.createdAt > $1.createdAt }).prefix(15) {
            let region = CLCircularRegion(center: .init(latitude: t.placeLat, longitude: t.placeLon), radius: 150, identifier: "orbit-" + key(t))
            region.notifyOnEntry = !t.placeOnLeave
            region.notifyOnExit = t.placeOnLeave
            places.append(UNNotificationRequest(identifier: prefix + "place-" + key(t), content: content(t, body: t.placeReminderText),
                                                trigger: UNLocationNotificationTrigger(region: region, repeats: false)))
        }
        #endif
        return (timed, places)
    }

    private static func key(_ t: TaskItem) -> String { t.uuid.isEmpty ? String(t.title.hashValue) : t.uuid }

    private static func content(_ t: TaskItem, body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = t.title
        c.body = body
        c.sound = .default
        c.userInfo = ["route": "tasks"]
        c.threadIdentifier = "tasks"
        return c
    }

    /// Place reminders need permission to use location while Orbit is in use; ask when the first one is set.
    static func ensureLocationAccess() {
        #if os(iOS)
        let m = CLLocationManager()
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
        #endif
    }
}
