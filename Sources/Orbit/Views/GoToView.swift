import SwiftUI
import SwiftData
import MapKit

extension PlaceCategory {
    var color: Color {
        switch self {
        case .food: Theme.orange
        case .cafe: Theme.peach
        case .bar: Theme.purple
        case .shop: Theme.pink
        case .museum: Theme.cyan
        case .park: Theme.lime
        case .attraction: Theme.mint
        case .hotel: Theme.blush
        case .other: Theme.card
        }
    }
}

/// Bucket list › Go to: places you liked or want to try, on a map and in a list.
struct GoToSection: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<BucketItem> { $0.kindRaw == "place" }, sort: \BucketItem.createdAt, order: .reverse) private var places: [BucketItem]
    @State private var category: PlaceCategory?
    @State private var showVisited = false
    @State private var selected: String?
    @State private var editing: BucketItem?
    @State private var adding = false
    @State private var camera: MapCameraPosition = .automatic

    private var shown: [BucketItem] {
        places.filter { (category == nil || $0.placeCategory == category) && $0.isDone == showVisited }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go to").font(Theme.display(24))
                    Text(places.isEmpty ? "Places you liked or want to try." : "\(places.filter { !$0.isDone }.count) to go · \(places.filter(\.isDone).count) been")
                        .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button { adding = true } label: { Label("Add place", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }

            if places.contains(where: \.hasLocation) { map }
            if Platform.isPhone, let file = Bundle.main.url(forResource: "Orbit Go To", withExtension: "shortcut", subdirectory: "Shortcuts") {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 34, height: 34).background(Circle().fill(Theme.mint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save from Google or Apple Maps").font(Theme.ui(14, weight: .semibold))
                        Text("Add the Orbit Go To shortcut once. Then in Maps, open a place › Share › Orbit Go To.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    ShareLink(item: file) { Text("Add").font(Theme.ui(13, weight: .semibold)) }.buttonStyle(SoftButtonStyle()).fixedSize()
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(showVisited ? "Been" : "To go", symbol: showVisited ? "checkmark.seal.fill" : "mappin", on: true, color: Theme.inverse, ink: Theme.onInverse) {
                        showVisited.toggle()
                    }
                    Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 2)
                    ForEach(PlaceCategory.allCases) { c in
                        let n = places.filter { $0.placeCategory == c && $0.isDone == showVisited }.count
                        if n > 0 {
                            chip("\(c.title) \(n)", symbol: c.symbol, on: category == nil || category == c, color: c.color, ink: Theme.stickerInk) {
                                category = category == c ? nil : c
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            if shown.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 36, weight: .light))
                    Text(places.isEmpty ? "Loved a restaurant, a shop or a museum? Add it by name or paste its Google or Apple Maps link, and it lands here on your map."
                                        : showVisited ? "No places ticked off yet." : "Nothing here in this filter.")
                        .font(Theme.ui(14)).multilineTextAlignment(.center)
                    if places.isEmpty { Button("Add your first place") { adding = true }.buttonStyle(SoftButtonStyle()) }
                }
                .foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(shown) { p in
                    PlaceCard(place: p, highlighted: selected == p.uuid)
                        .onTapGesture { editing = p }
                }
            }
        }
        .sheet(isPresented: $adding) { PlaceEditor(place: nil) }
        .sheet(item: $editing) { PlaceEditor(place: $0) }
    }

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            ForEach(places.filter { $0.hasLocation && (category == nil || $0.placeCategory == category) }) { p in
                Marker(p.title, systemImage: p.placeCategory.symbol, coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
                    .tint(p.isDone ? Color.gray : p.placeCategory.color == Theme.card ? Theme.ink : p.placeCategory.color)
                    .tag(p.uuid)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onAppear { fit() }
        .onChange(of: places.count) { fit() }
        .onChange(of: category) { fit() }
        .frame(height: Platform.isPhone ? 260 : 340)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: selected) { _, id in
            if let p = places.first(where: { $0.uuid == id }), p.isDone != showVisited { showVisited = p.isDone }
        }
    }

    /// Frames every pin, never closer than a neighbourhood (one pin alone would zoom to street level).
    private func fit() {
        let pins = places.filter { $0.hasLocation && (category == nil || $0.placeCategory == category) }
        guard !pins.isEmpty else { return }
        let lats = pins.map(\.latitude), lons = pins.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.03, (lats.max()! - lats.min()!) * 1.4),
                                    longitudeDelta: max(0.03, (lons.max()! - lons.min()!) * 1.4))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func chip(_ title: String, symbol: String, on: Bool, color: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(Theme.ui(12, weight: .medium)).foregroundStyle(ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(color.opacity(on ? 1 : 0.3)))
        }
        .buttonStyle(.plain)
    }
}

struct PlaceCard: View {
    @Bindable var place: BucketItem
    var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: place.placeCategory.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 40, height: 40).background(Circle().fill(place.placeCategory.color))
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).font(Theme.ui(16, weight: .semibold)).lineLimit(2)
                Text([place.placeCategory.title, place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                if !place.notes.isEmpty { Text(place.notes).font(Theme.ui(13)).lineLimit(3).padding(.top, 2) }
                HStack(spacing: 8) {
                    if let url = mapsURL {
                        Button { Platform.open(url) } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                            .buttonStyle(SoftButtonStyle())
                    }
                    Button {
                        withAnimation { place.isDone.toggle(); place.doneAt = place.isDone ? .now : nil }
                    } label: {
                        Label(place.isDone ? "Been there" : "Went", systemImage: place.isDone ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .font(Theme.ui(12, weight: .medium))
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink, lineWidth: highlighted ? 2 : 0))
        .contentShape(Rectangle())
    }

    private var mapsURL: URL? {
        if place.hasLocation {
            var c = URLComponents(string: "https://maps.apple.com/")!
            c.queryItems = [.init(name: "daddr", value: "\(place.latitude),\(place.longitude)"), .init(name: "q", value: place.title)]
            return c.url
        }
        return URL(string: place.mapURL).flatMap { $0.scheme == nil ? nil : $0 }
    }
}

// MARK: - Add / edit

/// Live suggestions from Apple Maps as you type.
@MainActor
final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func update(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).count < 2 || PlaceLookup.firstURL(in: text) != nil { results = []; return }
        completer.queryFragment = text
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

struct PlaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let place: BucketItem?

    @StateObject private var completer = PlaceCompleter()
    @State private var query = ""
    @State private var found: PlaceLookup.Found?
    @State private var name = ""
    @State private var category: PlaceCategory = .food
    @State private var notes = ""
    @State private var been = false
    @State private var looking = false
    @State private var message: String?
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(place == nil ? "Add a place" : "Edit place").font(Theme.display(26))
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                }
                if place == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                        TextField("Search a place, or paste a Google or Apple Maps link", text: $query)
                            .textFieldStyle(.plain).font(Theme.ui(15)).focused($searching).onSubmit { Task { await lookUp(query) } }
                            #if os(iOS)
                            .textInputAutocapitalization(.words).autocorrectionDisabled()
                            #endif
                        if looking { ProgressView().controlSize(.small) }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    .onChange(of: query) { _, q in
                        completer.update(q)
                        if PlaceLookup.firstURL(in: q) != nil { Task { await lookUp(q) } }
                    }
                    if found == nil && !completer.results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(completer.results, id: \.self) { r in
                                Button { Task { await pick(r) } } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(Theme.ui(14, weight: .medium)).foregroundStyle(Theme.ink)
                                        if !r.subtitle.isEmpty { Text(r.subtitle).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    }
                    if found == nil, completer.results.isEmpty, query.trimmingCharacters(in: .whitespaces).count >= 2, PlaceLookup.firstURL(in: query) == nil, !looking {
                        Button { Task { await lookUp(query) } } label: {
                            Label("Search Maps for “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    if let message { Text(message).font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                }

                if let c = found?.coordinate ?? (place?.hasLocation == true ? CLLocationCoordinate2D(latitude: place!.latitude, longitude: place!.longitude) : nil) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600))) {
                        Marker(name, systemImage: category.symbol, coordinate: c).tint(category.color == Theme.card ? Theme.ink : category.color)
                    }
                    .id("\(c.latitude),\(c.longitude)")
                    .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
                }

                if found != nil || place != nil || !name.isEmpty {
                    TextField("Name", text: $name).textFieldStyle(.plain).font(Theme.ui(16, weight: .semibold))
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    if let a = found?.address ?? place?.address, !a.isEmpty {
                        Label(a, systemImage: "mappin").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(PlaceCategory.allCases) { c in
                            Label(c.title, systemImage: c.symbol).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.stickerInk)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(c.color.opacity(category == c ? 1 : 0.35)))
                                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: category == c ? 1.5 : 0))
                                .onTapGesture { category = c }
                        }
                    }
                    TextField("What did you like? What to order, who to go with…", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain).font(Theme.ui(14)).lineLimit(2...6)
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    Toggle("I've been here", isOn: $been).font(Theme.ui(14))
                    HStack {
                        if let place {
                            Button("Delete", role: .destructive) { context.delete(place); dismiss() }.buttonStyle(SoftButtonStyle())
                        }
                        Spacer()
                        Button(place == nil ? "Save to Go to" : "Save", action: save)
                            .buttonStyle(PrimaryButtonStyle()).fixedSize()
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(Platform.isPhone ? 20 : 28)
        }
        .scrollIndicators(.never)
        .background(Theme.canvas)
        .sheetFrame(width: 520, height: 680)
        .onAppear {
            guard let place else { searching = true; return }
            name = place.title; category = place.placeCategory; notes = place.notes; been = place.isDone
        }
    }

    private func lookUp(_ text: String) async {
        looking = true; message = nil
        if let f = await PlaceLookup.resolve(text) { apply(f) }
        else { message = PlaceLookup.firstURL(in: text) != nil ? "Couldn't read that link. Try the place's name instead." : "No place found. Type its name below to save it anyway."
            if PlaceLookup.firstURL(in: text) == nil { name = text } }
        looking = false
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        looking = true
        let req = MKLocalSearch.Request(completion: completion)
        if let item = try? await MKLocalSearch(request: req).start().mapItems.first { apply(PlaceLookup.found(item, url: "")) }
        looking = false
    }

    private func apply(_ f: PlaceLookup.Found) {
        found = f; name = f.name; category = f.category
        completer.results = []
        searching = false
    }

    private func save() {
        let item = place ?? BucketItem(title: "", kind: .place)
        item.title = name.trimmingCharacters(in: .whitespaces)
        item.kind = .place
        item.placeCategory = category
        item.notes = notes
        if item.isDone != been { item.isDone = been; item.doneAt = been ? .now : nil }
        if let f = found {
            item.address = f.address
            if let c = f.coordinate { item.latitude = c.latitude; item.longitude = c.longitude }
            item.mapURL = f.url
        }
        if place == nil { context.insert(item) }
        dismiss()
    }
}
