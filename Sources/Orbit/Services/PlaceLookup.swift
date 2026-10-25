import Foundation
import MapKit
import SwiftData

/// Turns what you give Orbit (a Google or Apple Maps link, or just a name like "Zooba Zamalek") into a place with
/// coordinates, an address and a kind (food, café, shop, museum…), using Apple Maps, plus Google Maps when you've added
/// a Google Maps key (see GooglePlaces).
@MainActor
enum PlaceLookup {
    struct Found {
        var name: String
        var address: String
        var coordinate: CLLocationCoordinate2D?
        var category: PlaceCategory
        var url: String
    }

    /// A link or a name. Nil when nothing could be found.
    static func resolve(_ input: String) async -> Found? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let link = firstURL(in: text) {
            let named = await fromLink(link)
            if let named { return named }
        }
        guard let item = await search(text, near: nil).first else { return nil }
        return found(item, url: "")
    }

    static func found(_ item: MKMapItem, url: String) -> Found {
        let name = item.name ?? ""
        // A Google result keeps its Google Maps link and Google's address.
        let googleAddress = GooglePlaces.address(of: item)
        let google = googleAddress != nil
        return Found(name: name, address: googleAddress ?? address(item), coordinate: item.placemark.coordinate,
                     category: category(item.pointOfInterestCategory, name: name),
                     url: !url.isEmpty ? url : google ? item.url!.absoluteString : appleMapsURL(name: name, coordinate: item.placemark.coordinate))
    }

    static func search(_ query: String, near: CLLocationCoordinate2D?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let near { request.region = MKCoordinateRegion(center: near, latitudinalMeters: 1500, longitudinalMeters: 1500) }
        async let apple = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        async let google = GooglePlaces.search(query, near: near)
        return GooglePlaces.merged(apple: await apple, google: await google)
    }

    static func appleMapsURL(name: String, coordinate: CLLocationCoordinate2D) -> String {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [.init(name: "q", value: name), .init(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")]
        return c.url?.absoluteString ?? ""
    }

    // MARK: Links

    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let ns = text as NSString
        return detector?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.url
    }

    /// Google Maps (incl. maps.app.goo.gl short links) and Apple Maps links.
    private static func fromLink(_ link: URL) async -> Found? {
        var url = link
        let host = url.host?.lowercased() ?? ""
        if host.contains("goo.gl") || host == "g.co" || host.hasSuffix("page.link") {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            if let (_, response) = try? await URLSession.shared.data(for: req), let final = response.url { url = final }
        }
        let (name, coordinate) = parse(url)
        if name.isEmpty && coordinate == nil { return nil }
        // Ask Apple Maps for the same place to get its kind and address.
        if !name.isEmpty {
            let results = await search(name, near: coordinate)
            let best = results.min { distance($0, coordinate) < distance($1, coordinate) }
            if let best, coordinate == nil || distance(best, coordinate) < 400 {
                var f = found(best, url: link.absoluteString)
                f.name = name
                return f
            }
        }
        if let coordinate {
            let req = MKLocalPointsOfInterestRequest(center: coordinate, radius: 60)
            if let near = try? await MKLocalSearch(request: req).start().mapItems.min(by: { distance($0, coordinate) < distance($1, coordinate) }) {
                var f = found(near, url: link.absoluteString)
                if !name.isEmpty { f.name = name }
                return f
            }
            return Found(name: name.isEmpty ? "Pinned place" : name, address: "", coordinate: coordinate,
                         category: category(nil, name: name), url: link.absoluteString)
        }
        return Found(name: name, address: "", coordinate: nil, category: category(nil, name: name), url: link.absoluteString)
    }

    /// Pulls the place name and coordinates out of a maps URL.
    static func parse(_ url: URL) -> (name: String, coordinate: CLLocationCoordinate2D?) {
        let s = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value?.trimmingCharacters(in: .whitespaces) }
        func coord(_ text: String?) -> CLLocationCoordinate2D? {
            guard let parts = text?.split(separator: ",").map({ Double($0.trimmingCharacters(in: .whitespaces)) }), parts.count >= 2,
                  let lat = parts[0], let lon = parts[1], abs(lat) <= 90, abs(lon) <= 180, lat != 0 || lon != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        var name = "", coordinate: CLLocationCoordinate2D?

        if s.contains("maps.apple") {
            name = q("q") ?? q("name") ?? ""
            coordinate = coord(q("ll")) ?? coord(q("coordinate")) ?? coord(q("sll"))
            if name.isEmpty, let a = q("address") { name = a }
        } else {
            // google.com/maps/place/Zooba+Zamalek/@30.06,31.22,17z/data=...!3d30.0612!4d31.2195
            if let r = s.range(of: #"/place/([^/@]+)"#, options: .regularExpression) {
                name = String(s[r]).replacingOccurrences(of: "/place/", with: "").replacingOccurrences(of: "+", with: " ")
            }
            if let r = s.range(of: #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#, options: .regularExpression) {
                let parts = s[r].replacingOccurrences(of: "!3d", with: "").replacingOccurrences(of: "!4d", with: ",")
                coordinate = coord(parts)
            } else if let r = s.range(of: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#, options: .regularExpression) {
                coordinate = coord(String(s[r].dropFirst()))
            }
            if name.isEmpty, let query = q("q") ?? q("query") {
                if let c = coord(query) { coordinate = coordinate ?? c } else { name = query.replacingOccurrences(of: "+", with: " ") }
            }
        }
        return (name.trimmingCharacters(in: .whitespaces), coordinate)
    }

    private static func distance(_ item: MKMapItem, _ to: CLLocationCoordinate2D?) -> Double {
        guard let to else { return 0 }
        let a = item.placemark.coordinate
        return CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    private static func address(_ item: MKMapItem) -> String {
        let p = item.placemark
        let parts = [p.thoroughfare.map { [p.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") }, p.subLocality, p.locality]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: Kind

    static func category(_ poi: MKPointOfInterestCategory?, name: String) -> PlaceCategory {
        switch poi {
        case .restaurant?, .bakery?: return .food
        case .cafe?: return .cafe
        case .nightlife?, .brewery?, .winery?: return .bar
        case .store?, .foodMarket?: return .shop
        case .museum?: return .museum
        case .park?, .nationalPark?, .beach?, .campground?, .marina?: return .park
        case .amusementPark?, .aquarium?, .zoo?, .theater?, .movieTheater?, .stadium?: return .attraction
        case .hotel?: return .hotel
        default: break
        }
        let n = name.lowercased()
        let words: [(PlaceCategory, [String])] = [
            (.cafe, ["cafe", "café", "coffee", "roaster", "tea house", "كافيه", "قهوة"]),
            (.bar, [" bar", "pub", "lounge", "rooftop"]),
            (.food, ["restaurant", "kitchen", "grill", "pizza", "burger", "sushi", "bistro", "diner", "koshary", "شاورما", "مطعم"]),
            (.museum, ["museum", "gallery", "متحف"]),
            (.shop, ["mall", "store", "shop", "market", "boutique", "outlet"]),
            (.park, ["park", "garden", "beach", "حديقة"]),
            (.hotel, ["hotel", "resort", "inn", "hostel", "فندق"]),
            (.attraction, ["temple", "pyramid", "castle", "citadel", "tower", "palace", "cinema", "theatre", "theater", "zoo"]),
        ]
        return words.first { _, ws in ws.contains { n.contains($0) } }?.0 ?? .other
    }

    /// Saves a Go to place from a link or a name (used by the assistant and the Shortcuts action).
    static func add(_ input: String, notes: String = "", category: PlaceCategory? = nil, context: ModelContext) async -> BucketItem? {
        let f = await resolve(input)
        let fallbackName = firstURL(in: input) == nil ? input.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard let name = f?.name.nilIfEmpty ?? fallbackName.nilIfEmpty else { return nil }
        let item = BucketItem(title: name, kind: .place, notes: notes)
        item.placeCategory = category ?? f?.category ?? self.category(nil, name: name)
        item.address = f?.address ?? ""
        if let c = f?.coordinate { item.latitude = c.latitude; item.longitude = c.longitude }
        item.mapURL = f?.url ?? (firstURL(in: input)?.absoluteString ?? "")
        context.insert(item)
        try? context.save()
        return item
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
