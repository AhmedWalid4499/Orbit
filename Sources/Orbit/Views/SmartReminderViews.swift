import SwiftUI
import MapKit

/// Search Apple Maps for a place and pick it (for place reminders, and Home and Work in Settings).
struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var onPick: (PlaceLookup.Found) -> Void

    @StateObject private var completer = PlaceCompleter()
    @State private var query = ""
    @State private var looking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(Theme.display(24))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                TextField("Search an address, place or shop", text: $query)
                    .textFieldStyle(.plain).font(Theme.ui(15)).focused($focused)
                    .onSubmit { Task { await search(query) } }
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif
                if looking { ProgressView().controlSize(.small) }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .onChange(of: query) { _, q in completer.update(q) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completer.results, id: \.self) { r in
                        Button { Task { await pick(r) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(Theme.ui(14, weight: .medium)).foregroundStyle(Theme.ink)
                                if !r.subtitle.isEmpty { Text(r.subtitle).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .padding(Platform.isPhone ? 20 : 24)
        .sheetFrame(width: 460, height: 520)
        .onAppear { focused = true }
    }

    private func pick(_ c: MKLocalSearchCompletion) async {
        looking = true
        if let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first {
            onPick(PlaceLookup.found(item, url: ""))
            dismiss()
        }
        looking = false
    }

    private func search(_ text: String) async {
        looking = true
        if let f = await PlaceLookup.resolve(text), f.coordinate != nil { onPick(f); dismiss() }
        looking = false
    }
}

/// Task editor › Remind me: at a time, and/or when you arrive at or leave a place.
struct ReminderSection: View {
    @Bindable var task: TaskItem
    @State private var searching = false
    @State private var hasTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remind me").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            HStack {
                Toggle(isOn: $hasTime) { Label("At a time", systemImage: "alarm") }.font(Theme.ui(13))
                Spacer()
                if hasTime {
                    DatePicker("", selection: Binding(get: { task.remindAt ?? defaultTime }, set: { task.remindAt = $0 }),
                               displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                }
            }
            HStack(spacing: 8) {
                Menu {
                    if let home = SavedPlaces.home { Button("Home · \(home.address)") { set("Home", home.lat, home.lon) } }
                    else { Button("Home (set it in Settings › General)") {}.disabled(true) }
                    if let work = SavedPlaces.work { Button("Work · \(work.address)") { set("Work", work.lat, work.lon) } }
                    else { Button("Work (set it in Settings › General)") {}.disabled(true) }
                    Button("Search a place…") { searching = true }
                    if task.hasPlaceReminder {
                        Divider()
                        Button("No place reminder", role: .destructive) { task.placeName = ""; task.placeLat = 0; task.placeLon = 0 }
                    }
                } label: {
                    Label(task.hasPlaceReminder ? task.placeName : "At a place", systemImage: "location.fill").font(Theme.ui(13, weight: .medium))
                }
                .fixedSize()
                if task.hasPlaceReminder {
                    Picker("", selection: $task.placeOnLeave) { Text("When I arrive").tag(false); Text("When I leave").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
            }
            if task.hasPlaceReminder && !Platform.isPhone {
                Text("Place reminders go off on your iPhone.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
        }
        .onAppear { hasTime = task.remindAt != nil }
        .onChange(of: hasTime) { _, on in task.remindAt = on ? (task.remindAt ?? defaultTime) : nil }
        .sheet(isPresented: $searching) {
            PlaceSearchSheet(title: "Remind me at…") { f in
                if let c = f.coordinate { set(f.name, c.latitude, c.longitude) }
            }
        }
    }

    /// The due day at 9:00, or an hour from now.
    private var defaultTime: Date {
        if let due = task.due, due > .now { return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due }
        return Date.now.addingTimeInterval(3600)
    }

    private func set(_ name: String, _ lat: Double, _ lon: Double) {
        task.placeName = name; task.placeLat = lat; task.placeLon = lon
        SmartReminders.ensureLocationAccess()
    }
}

/// Settings › General › Places: Home and Work for "remind me when I get home".
struct SavedPlacesSection: View {
    @State private var home = SavedPlaces.home
    @State private var work = SavedPlaces.work
    @State private var editing: String?

    var body: some View {
        Section {
            row("Home", "house.fill", home) { editing = "home" } clear: { SavedPlaces.set("home", nil); home = nil }
            row("Work", "briefcase.fill", work) { editing = "work" } clear: { SavedPlaces.set("work", nil); work = nil }
        } header: {
            Text("Places")
        } footer: {
            Text("Used for reminders like “remind me to call mom when I get home”.")
        }
        .sheet(item: Binding(get: { editing.map { EditingKey(id: $0) } }, set: { editing = $0?.id })) { key in
            PlaceSearchSheet(title: key.id == "home" ? "Your home" : "Your work") { f in
                guard let c = f.coordinate else { return }
                let p = SavedPlaces.Place(name: key.id == "home" ? "Home" : "Work", address: f.address.isEmpty ? f.name : f.address,
                                          lat: c.latitude, lon: c.longitude)
                SavedPlaces.set(key.id, p)
                if key.id == "home" { home = p } else { work = p }
                SmartReminders.ensureLocationAccess()
            }
        }
    }

    private struct EditingKey: Identifiable { let id: String }

    private func row(_ title: String, _ symbol: String, _ place: SavedPlaces.Place?, edit: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(place?.address ?? "Not set").foregroundStyle(.secondary).lineLimit(1)
            Button(place == nil ? "Set" : "Change", action: edit)
            if place != nil { Button(role: .destructive, action: clear) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
        }
    }
}
