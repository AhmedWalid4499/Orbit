import SwiftUI
import SwiftData

// MARK: - Trips on the bucket list

struct TripsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.createdAt) private var trips: [Trip]
    @Query private var bookings: [Booking]
    @Query private var transactions: [Transaction]
    @Binding var open: Trip?

    private var sorted: [Trip] {
        trips.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            .filter { ($0.end ?? $0.start ?? .distantFuture) >= Date.now.startOfDay.adding(days: -14) }
    }
    private var unassigned: [Booking] { bookings.filter { $0.tripUUID.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trips").font(Theme.display(22))
                Spacer()
                Button {
                    let t = Trip(title: "New trip"); t.uuid = UUID().uuidString.lowercased(); t.packing = TripStore.basics
                    context.insert(t); open = t
                } label: { Label("New trip", systemImage: "plus") }
                .buttonStyle(SoftButtonStyle())
            }
            if sorted.isEmpty {
                Text("Plan a trip from a travel dream below, or start a new one. Flights and hotels from your email are added by themselves.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(sorted) { t in
                        TripCard(trip: t, bookings: bookings.filter { $0.tripUUID == t.uuid },
                                 spent: TripStore.spent(t, bookings: bookings, transactions: transactions))
                            .onTapGesture { open = t }
                    }
                }
            }
            .scrollIndicators(.never)
            if !unassigned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Found in your email", systemImage: "envelope.fill").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    ForEach(unassigned) { b in
                        HStack(spacing: 10) {
                            Image(systemName: b.kind.symbol).frame(width: 20)
                            Text(b.title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                            if let s = b.start { Text(s.formatted(.dateTime.day().month(.abbreviated))).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary) }
                            Spacer()
                            Menu("Add to trip") {
                                ForEach(trips) { t in Button(t.title) { b.tripUUID = t.uuid } }
                                Divider()
                                Button("New trip") {
                                    let t = Trip(title: b.location.isEmpty ? b.title : b.location, destination: b.location)
                                    t.uuid = UUID().uuidString.lowercased(); t.start = b.start?.startOfDay; t.end = b.end?.startOfDay
                                    t.packing = TripStore.basics
                                    context.insert(t); b.tripUUID = t.uuid; open = t
                                }
                                Button("Not a trip", role: .destructive) { context.delete(b) }
                            }
                            .fixedSize()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    }
                }
            }
        }
    }
}

struct TripCard: View {
    let trip: Trip
    let bookings: [Booking]
    let spent: Double

    var body: some View {
        let days = TripStore.daysUntil(trip)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title).font(Theme.display(20)).lineLimit(1)
                    Text([trip.destination, dates].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.ui(12)).opacity(0.75).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let days {
                    VStack(spacing: 0) {
                        Text(days < 0 ? "✈️" : days == 0 ? "🎉" : "\(days)").font(Theme.display(26))
                        Text(days < 0 ? "now" : days == 0 ? "today" : days == 1 ? "day" : "days").font(Theme.ui(10, weight: .semibold)).opacity(0.7)
                    }
                }
            }
            HStack(spacing: 12) {
                Label("\(trip.packed.count)/\(trip.packing.count) packed", systemImage: "suitcase.fill")
                Label("\(bookings.count) booking\(bookings.count == 1 ? "" : "s")", systemImage: "ticket.fill")
            }
            .font(Theme.ui(11, weight: .semibold)).opacity(0.8)
            if trip.budget > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.5))
                            Capsule().fill(spent > trip.budget ? Theme.critical : Theme.stickerInk).frame(width: g.size.width * min(1, spent / trip.budget))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Fmt.money(spent)) of \(Fmt.money(trip.budget))").font(Theme.ui(11, weight: .semibold)).opacity(0.8)
                }
            }
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16)
        .frame(width: 290, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cyan))
    }

    private var dates: String {
        guard let s = trip.start else { return "" }
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        guard let e = trip.end, !e.isSameDay(as: s) else { return s.formatted(f) }
        return "\(s.formatted(f)) – \(e.formatted(f))"
    }
}

// MARK: - Trip detail

struct TripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var trip: Trip
    @Query private var bookings: [Booking]
    @Query private var transactions: [Transaction]

    @State private var newItem = ""
    @State private var editing: Booking?
    @State private var addingBooking = false
    @State private var suggesting = false
    @State private var error: String?
    @State private var budgetText = ""

    private var mine: [Booking] {
        bookings.filter { $0.tripUUID == trip.uuid && !trip.uuid.isEmpty }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    titleBlock
                    Spacer()
                    stat
                }
                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    stat
                }
            }
            FlowLayout(spacing: 14) {
                dateField("From", $trip.start)
                dateField("To", $trip.end)
                HStack(spacing: 6) {
                    Text("Budget").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    TextField("0", text: $budgetText).textFieldStyle(.roundedBorder).frame(width: 90)
                        .onSubmit { trip.budget = Double(budgetText.replacingOccurrences(of: ",", with: "")) ?? 0 }
                        .onChange(of: budgetText) { trip.budget = Double(budgetText.replacingOccurrences(of: ",", with: "")) ?? 0 }
                    Text(Fmt.currencyCode).font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                }
            }
            #if os(iOS)
            VStack(alignment: .leading, spacing: 18) {
                bookingsColumn.frame(height: 300)
                packingColumn.frame(height: 440)
            }
            #else
            HStack(alignment: .top, spacing: 16) {
                bookingsColumn
                packingColumn
            }
            .frame(maxHeight: .infinity)
            #endif
            TextField("Notes: where to stay, what to see, who's coming…", text: $trip.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...3).font(Theme.ui(13))
            HStack {
                Button("Delete trip", role: .destructive) {
                    for b in mine { b.tripUUID = "" }
                    context.delete(trip); dismiss()
                }
                .buttonStyle(SoftButtonStyle())
                if let error { Text(error).font(Theme.ui(11)).foregroundStyle(Theme.critical).lineLimit(2) }
                Spacer()
                Button("Done") { try? context.save(); dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .phoneScrollable()
        .sheetFrame(width: 820, height: 720)
        .onAppear { if trip.budget > 0 { budgetText = trip.budget.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } }
        .sheet(item: $editing) { BookingEditor(booking: $0, tripUUID: trip.uuid) }
        .sheet(isPresented: $addingBooking) { BookingEditor(booking: nil, tripUUID: trip.uuid) }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Trip name", text: $trip.title).textFieldStyle(.plain).font(Theme.display(28))
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.inkMuted)
                TextField("Destination, e.g. Lisbon", text: $trip.destination).textFieldStyle(.plain).font(Theme.ui(14))
            }
        }
    }

    private var stat: some View {
        let spent = TripStore.spent(trip, bookings: bookings, transactions: transactions)
        return FlowLayout(spacing: 10) {
            if let d = TripStore.daysUntil(trip), d >= 0 { pill(d == 0 ? "Today!" : "\(d) day\(d == 1 ? "" : "s") to go", Theme.lime) }
            if let n = trip.nights, n > 0 { pill("\(n) night\(n == 1 ? "" : "s")", Theme.pink) }
            pill(trip.budget > 0 ? "\(Fmt.money(spent)) of \(Fmt.money(trip.budget))" : "\(Fmt.money(spent)) spent",
                 trip.budget > 0 && spent > trip.budget ? Theme.orange : Theme.cyan)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(color))
    }

    private func dateField(_ label: String, _ date: Binding<Date?>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            if date.wrappedValue != nil {
                DatePicker("", selection: Binding(get: { date.wrappedValue ?? .now }, set: { date.wrappedValue = $0.startOfDay }), displayedComponents: .date)
                    .labelsHidden()
                Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
            } else {
                Button("Set date") { date.wrappedValue = (label == "To" ? (trip.start ?? .now).adding(days: 4) : Date.now.adding(days: 30)).startOfDay }
                    .buttonStyle(SoftButtonStyle())
            }
        }
    }

    private var bookingsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bookings").font(Theme.ui(15, weight: .semibold))
                Spacer()
                Button { addingBooking = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }
            ScrollView {
                VStack(spacing: 6) {
                    if mine.isEmpty {
                        Text("Flights and hotels in your email show up here by themselves. You can also add them by hand.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(mine) { b in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: b.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                                .frame(width: 30, height: 30).background(Circle().fill(Theme.cyan))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(b.title).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                                    if b.source == "email" {
                                        Text("from email").font(Theme.ui(9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.canvas))
                                    }
                                }
                                Text([b.start.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) } ?? "",
                                      b.confirmation.isEmpty ? "" : "Ref \(b.confirmation)", b.provider]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                            }
                            Spacer()
                            if b.amount > 0 { Text(Fmt.money(b.amount)).font(Theme.ui(12, weight: .semibold)) }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = b }
                        .contextMenu {
                            Button("Remove from trip") { b.tripUUID = "" }
                            Button("Delete", role: .destructive) { context.delete(b) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity)
    }

    private var packingColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Packing").font(Theme.ui(15, weight: .semibold))
                Text("\(trip.packed.count)/\(trip.packing.count)").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button {
                    suggesting = true; error = nil
                    Task {
                        do {
                            let more = try await TripStore.suggestPacking(for: trip)
                            withAnimation { trip.packing += more }
                        } catch { self.error = error.localizedDescription }
                        suggesting = false
                    }
                } label: { Label(suggesting ? "Thinking…" : "Suggest", systemImage: "sparkles") }
                .buttonStyle(SoftButtonStyle()).disabled(suggesting)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                TextField("Add an item", text: $newItem).textFieldStyle(.plain).font(Theme.ui(13))
                    .onSubmit {
                        let t = newItem.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty && !trip.packing.contains(t) { trip.packing.append(t) }
                        newItem = ""
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(trip.packing, id: \.self) { item in
                        let isPacked = trip.packed.contains(item)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.snappy) { if isPacked { trip.packed.removeAll { $0 == item } } else { trip.packed.append(item) } }
                            } label: { CheckCircle(isOn: isPacked) }
                            .buttonStyle(.plain)
                            Text(item).font(Theme.ui(13)).strikethrough(isPacked, color: Theme.inkMuted)
                                .foregroundStyle(isPacked ? Theme.inkMuted : Theme.ink)
                            Spacer()
                            Button { trip.packing.removeAll { $0 == item }; trip.packed.removeAll { $0 == item } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(Theme.inkMuted).font(.system(size: 10))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BookingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let booking: Booking?
    let tripUUID: String

    @State private var kind: BookingKind = .flight
    @State private var title = ""
    @State private var provider = ""
    @State private var confirmation = ""
    @State private var location = ""
    @State private var hasStart = true
    @State private var start = Date.now.adding(days: 30)
    @State private var hasEnd = false
    @State private var end = Date.now.adding(days: 33)
    @State private var amount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(booking == nil ? "New booking" : "Edit booking").font(Theme.display(24))
            HStack(spacing: 6) {
                ForEach(BookingKind.allCases) { k in
                    Label(k.title, systemImage: k.symbol).font(Theme.ui(12, weight: .medium))
                        .foregroundStyle(kind == k ? Theme.onInverse : Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(kind == k ? Theme.inverse : Theme.card))
                        .onTapGesture { kind = k }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("What").foregroundStyle(Theme.inkSecondary); TextField("Cairo → Lisbon, MS777", text: $title).textFieldStyle(.roundedBorder) }
                GridRow { Text("With").foregroundStyle(Theme.inkSecondary); TextField("Airline, hotel, company", text: $provider).textFieldStyle(.roundedBorder) }
                GridRow { Text("Where").foregroundStyle(Theme.inkSecondary); TextField("City or address", text: $location).textFieldStyle(.roundedBorder) }
                GridRow { Text("Reference").foregroundStyle(Theme.inkSecondary); TextField("Booking code", text: $confirmation).textFieldStyle(.roundedBorder) }
                GridRow {
                    Text(kind == .hotel ? "Check-in" : "Starts").foregroundStyle(Theme.inkSecondary)
                    HStack { Toggle("", isOn: $hasStart).labelsHidden(); if hasStart { DatePicker("", selection: $start).labelsHidden() } }
                }
                GridRow {
                    Text(kind == .hotel ? "Check-out" : "Ends").foregroundStyle(Theme.inkSecondary)
                    HStack { Toggle("", isOn: $hasEnd).labelsHidden(); if hasEnd { DatePicker("", selection: $end).labelsHidden() } }
                }
                GridRow {
                    Text("Cost").foregroundStyle(Theme.inkSecondary)
                    HStack { TextField("0", text: $amount).textFieldStyle(.roundedBorder).frame(width: 120); Text(Fmt.currencyCode).foregroundStyle(Theme.inkMuted) }
                }
            }
            .font(Theme.ui(13))
            HStack {
                if let booking { Button("Delete", role: .destructive) { context.delete(booking); dismiss() }.buttonStyle(SoftButtonStyle()) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26).sheetFrame(width: 560)
        .onAppear {
            guard let b = booking else { return }
            kind = b.kind; title = b.title; provider = b.provider; confirmation = b.confirmation; location = b.location
            if let s = b.start { start = s } else { hasStart = false }
            if let e = b.end { end = e; hasEnd = true }
            if b.amount > 0 { amount = b.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        }
    }

    private func save() {
        let b = booking ?? { let b = Booking(title: ""); b.tripUUID = tripUUID; context.insert(b); return b }()
        b.kind = kind; b.title = title.trimmingCharacters(in: .whitespaces); b.provider = provider; b.confirmation = confirmation
        b.location = location; b.start = hasStart ? start : nil; b.end = hasEnd ? end : nil
        b.amount = abs(Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0)
        try? context.save()
        dismiss()
    }
}
