import Foundation
import CoreLocation
import MapKit
import SwiftData

/// "I'm hungry": finds food (or anything else) near you with Apple Maps, for the assistant to recommend from.
/// Your location stays on the device; only the place results go into the conversation.
@MainActor
final class NearbyFinder: NSObject, CLLocationManagerDelegate {
    static let shared = NearbyFinder()

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var lastFix: CLLocation?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    enum Where { case here(CLLocation), city(CLLocation, String), unknown(String) }

    /// Where you are now; if location is off, the weather city from Settings.
    func locate() async -> Where {
        if let fix = await currentLocation() { return .here(fix) }
        let city = WeatherStore.shared.effectiveCity
        if let p = try? await CLGeocoder().geocodeAddressString(city).first, let loc = p.location { return .city(loc, city) }
        return .unknown(manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
                        ? "Location is off for Orbit" : "Couldn't get your location")
    }

    private func currentLocation() async -> CLLocation? {
        if let lastFix, Date.now.timeIntervalSince(lastFix.timestamp) < 5 * 60 { return lastFix }
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return await withCheckedContinuation { c in
            waiting.append(c)
            manager.requestLocation()
            // Don't keep the conversation waiting if the fix is slow.
            Task { try? await Task.sleep(for: .seconds(12)); self.finish(nil) }
        }
    }

    private func finish(_ loc: CLLocation?) {
        if let loc { lastFix = loc }
        let w = waiting
        waiting = []
        for c in w { c.resume(returning: loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finish(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let s = manager.authorizationStatus
            if s == .denied || s == .restricted { self.finish(nil) }
            else if !self.waiting.isEmpty, s != .notDetermined { manager.requestLocation() }
        }
    }

    // MARK: Search

    struct Place {
        let name: String
        let kind: String
        let meters: Double
        let address: String
        let phone: String
        let website: String
        let mapsURL: String
        let saved: Bool
    }

    static let foodCategories: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery]

    /// Up to `limit` places matching `query` ("food", "sushi", "coffee", "pharmacy"…), nearest first.
    func search(_ query: String, near loc: CLLocation, radius: Double, limit: Int, context: ModelContext) async -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let generic = ["", "food", "eat", "restaurant", "restaurants", "hungry", "something to eat", "lunch", "dinner", "breakfast"].contains(q)
        let region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        var items: [MKMapItem] = []
        if generic {
            let r = MKLocalPointsOfInterestRequest(center: loc.coordinate, radius: radius)
            r.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.foodCategories)
            items = (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        }
        if items.count < limit {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = generic ? "restaurant" : query
            r.region = region
            r.resultTypes = .pointOfInterest
            items += (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        }
        let saved = Set(((try? context.fetch(FetchDescriptor<BucketItem>())) ?? []).filter { $0.kind == .place }.map { $0.title.lowercased() })
        var seen = Set<String>()
        return items
            .map { ($0, loc.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))) }
            .filter { $0.1 <= radius * 1.6 }
            .sorted { $0.1 < $1.1 }
            .compactMap { item, meters -> Place? in
                let name = item.name ?? ""
                guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
                let p = item.placemark
                let address = [p.thoroughfare.map { [p.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") }, p.subLocality]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                return Place(name: name, kind: Self.describe(item.pointOfInterestCategory), meters: meters, address: address,
                             phone: item.phoneNumber ?? "", website: item.url?.absoluteString ?? "",
                             mapsURL: PlaceLookup.appleMapsURL(name: name, coordinate: p.coordinate), saved: saved.contains(name.lowercased()))
            }
            .prefix(limit).map { $0 }
    }

    static func describe(_ c: MKPointOfInterestCategory?) -> String {
        switch c {
        case .restaurant?: "restaurant"
        case .cafe?: "café"
        case .bakery?: "bakery"
        case .foodMarket?: "food market"
        case .nightlife?: "bar"
        case .store?: "shop"
        case .pharmacy?: "pharmacy"
        case .museum?: "museum"
        case .park?: "park"
        default: c.map { $0.rawValue.replacingOccurrences(of: "MKPOICategory", with: "").lowercased() } ?? "place"
        }
    }

    static func distance(_ m: Double) -> String {
        m < 950 ? "\(Int((m / 10).rounded() * 10)) m" : String(format: "%.1f km", m / 1000)
    }

    /// The text the assistant tool returns.
    func lookup(_ query: String, radius: Double, context: ModelContext) async -> (text: String, isError: Bool) {
        let place = await locate()
        let loc: CLLocation, whereText: String
        switch place {
        case .here(let l): loc = l; whereText = "near the user's current location"
        case .city(let l, let city): loc = l; whereText = "in \(city) (the user's location is off, so this is around the centre of their weather city; mention that and that they can allow location for Orbit)"
        case .unknown(let why): return ("\(why). Ask the user which area they're in, then search again with that area in the query.", true)
        }
        let results = await search(query, near: loc, radius: max(300, min(radius, 15000)), limit: 10, context: context)
        if results.isEmpty { return ("No \(query) found within \(Self.distance(radius)) \(whereText). Try a wider radius or another kind of place.", false) }
        let favorites = ((try? context.fetch(FetchDescriptor<BucketItem>())) ?? []).filter { $0.kind == .place && $0.placeCategory == .food }
        var lines = ["Places for “\(query)” \(whereText), nearest first. Apple Maps doesn't give ratings, so recommend from the name, kind, distance and what you know about well-known places. Link each place you mention with its maps link in markdown, like [Name](link)."]
        lines += results.map { p in
            "- \(p.name) · \(p.kind) · \(Self.distance(p.meters))\(p.address.isEmpty ? "" : " · \(p.address)")\(p.saved ? " · already on their Go to list" : "") · maps: \(p.mapsURL)"
        }
        if !favorites.isEmpty { lines.append("Food places they saved before (their taste): " + favorites.prefix(8).map(\.title).joined(separator: ", ")) }
        return (lines.joined(separator: "\n"), false)
    }
}
