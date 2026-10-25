import Foundation
import MapKit
import SwiftUI

/// Google Maps as a second source for places, next to Apple Maps. Google knows far more shops, cafés and restaurants in
/// Egypt, with ratings. Needs a Google Maps Platform key (Places API (New)); without one, Orbit uses Apple Maps alone.
enum GooglePlaces {
    static let keyName = "google-maps-key"
    static var key: String? { Keychain.read(keyName).flatMap { $0.isEmpty ? nil : $0 } }
    static var isOn: Bool { key != nil }
    /// Address and rating of Google results, by their Google Maps link (MKMapItem has no field for them).
    @MainActor static var details: [String: (address: String, rating: String)] = [:]

    /// Places matching `query`, near `center` when given, as map items (their `url` is the Google Maps page).
    @MainActor static func search(_ query: String, near center: CLLocationCoordinate2D?, radius: Double = 2000, limit: Int = 10) async -> [MKMapItem] {
        guard let key, !Snapshot.isActive, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var req = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.displayName,places.formattedAddress,places.location,places.primaryType,places.googleMapsUri,places.rating,places.userRatingCount",
                     forHTTPHeaderField: "X-Goog-FieldMask")
        var body: [String: Any] = ["textQuery": query, "maxResultCount": min(20, limit)]
        if let c = center {
            body["locationBias"] = ["circle": ["center": ["latitude": c.latitude, "longitude": c.longitude], "radius": min(50000, radius)]]
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200,
              let places = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["places"] as? [[String: Any]] else { return [] }
        return places.compactMap { p in
            guard let loc = p["location"] as? [String: Any], let lat = loc["latitude"] as? Double, let lon = loc["longitude"] as? Double else { return nil }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            item.name = (p["displayName"] as? [String: Any])?["text"] as? String
            item.url = (p["googleMapsUri"] as? String).flatMap(URL.init(string:))
            let rating = (p["rating"] as? Double).map { String(format: "%.1f★ (%d)", $0, p["userRatingCount"] as? Int ?? 0) } ?? ""
            if let u = item.url?.absoluteString { details[u] = (p["formattedAddress"] as? String ?? "", rating) }
            item.pointOfInterestCategory = category(p["primaryType"] as? String ?? "")
            return item
        }
    }

    /// Apple and Google results together, Google first, without the same place twice.
    static func merged(apple: [MKMapItem], google: [MKMapItem]) -> [MKMapItem] {
        var out = google
        for a in apple where !google.contains(where: { same($0, a) }) { out.append(a) }
        return out
    }

    static func same(_ a: MKMapItem, _ b: MKMapItem) -> Bool {
        let d = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
            .distance(from: CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude))
        let n1 = (a.name ?? "").lowercased(), n2 = (b.name ?? "").lowercased()
        return d < 80 && (n1.contains(n2) || n2.contains(n1) || n1.prefix(6) == n2.prefix(6))
    }

    /// Google's address (with its rating) for a Google result, else nil.
    @MainActor static func address(of item: MKMapItem) -> String? {
        guard let u = item.url?.absoluteString, let d = details[u] else { return nil }
        return [d.address, d.rating].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A Google Maps link for any place (works without a key).
    static func mapsURL(name: String, coordinate: CLLocationCoordinate2D?) -> String {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        c.queryItems = [.init(name: "api", value: "1"),
                        .init(name: "query", value: coordinate.map { "\(name) \($0.latitude),\($0.longitude)" } ?? name)]
        return c.url?.absoluteString ?? ""
    }

    private static func category(_ type: String) -> MKPointOfInterestCategory? {
        switch type {
        case let t where t.contains("cafe") || t.contains("coffee"): .cafe
        case let t where t.contains("bakery"): .bakery
        case let t where t.contains("restaurant") || t.contains("food"): .restaurant
        case let t where t.contains("museum"): .museum
        case let t where t.contains("park"): .park
        case let t where t.contains("pharmacy"): .pharmacy
        case let t where t.contains("gym") || t.contains("fitness"): .fitnessCenter
        case let t where t.contains("hotel") || t.contains("lodging"): .hotel
        case let t where t.contains("store") || t.contains("shop") || t.contains("mall"): .store
        case let t where t.contains("bar") || t.contains("night_club"): .nightlife
        case let t where t.contains("hospital") || t.contains("doctor"): .hospital
        case let t where t.contains("school") || t.contains("university"): .university
        default: nil
        }
    }
}

/// Settings › Connections › Google Maps: the optional key that adds Google as a second place source.
struct GoogleMapsConnectionRow: View {
    @State private var key = ""
    @State private var on = GooglePlaces.isOn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                BrandLogo(brand: .googleMaps, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Maps").font(.headline)
                    Text(on ? "The assistant searches Google Maps and Apple Maps together." : "Apple Maps is on. Add a Google Maps key to search both.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if on { Button("Disconnect", role: .destructive) { Keychain.delete(GooglePlaces.keyName); on = false } }
            }
            if !on {
                HStack {
                    SecureField("Google Maps API key", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save") {
                        Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: GooglePlaces.keyName)
                        key = ""; on = GooglePlaces.isOn
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Google Cloud › APIs & Services: turn on “Places API (New)”, then Credentials › Create API key. Google's monthly free credit covers personal use.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
