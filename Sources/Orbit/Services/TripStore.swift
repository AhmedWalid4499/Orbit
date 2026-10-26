import SwiftUI
import SwiftData

/// Trips: bookings (by hand or from email), a packing list and a budget.
@MainActor
enum TripStore {
    private static let dayTime: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func parse(_ s: String) -> Date? { dayTime.date(from: s) ?? day.date(from: s).map { $0.adding(minutes: 12 * 60) } }

    /// Adds a booking found in email (once per email) and files it under the matching trip, if any.
    static func recordBooking(kind: BookingKind, title: String, provider: String, place: String, start: String, end: String,
                              confirmation: String, amount: Double, emailID: String, context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Booking>())) ?? []
        guard !existing.contains(where: { $0.sourceID == emailID }) else { return }
        let b = Booking(title: title, kind: kind)
        b.provider = provider; b.location = place; b.confirmation = confirmation; b.amount = amount
        b.start = parse(start); b.end = parse(end)
        b.source = "email"; b.sourceID = emailID
        b.tripUUID = match(b, trips: (try? context.fetch(FetchDescriptor<Trip>())) ?? [])?.uuid ?? ""
        context.insert(b)
    }

    /// The trip a booking most likely belongs to: its dates cover the booking, or the destination matches.
    static func match(_ b: Booking, trips: [Trip]) -> Trip? {
        let byDate = trips.first { t in
            guard let s = t.start, let when = b.start else { return false }
            let e = t.end ?? s
            return when >= s.startOfDay.adding(days: -2) && when < e.startOfDay.adding(days: 2)
        }
        if let byDate { return byDate }
        let text = "\(b.title) \(b.location)".lowercased()
        return trips.first { !$0.destination.isEmpty && text.contains($0.destination.lowercased()) }
    }

    /// Bookings plus expenses dated during the trip (not counting an expense that is itself a booking).
    static func spent(_ trip: Trip, bookings: [Booking], transactions: [Transaction]) -> Double {
        let mine = bookings.filter { $0.tripUUID == trip.uuid && !trip.uuid.isEmpty }
        var total = mine.reduce(0) { $0 + $1.amount }
        if let s = trip.start {
            let e = (trip.end ?? s).startOfDay.adding(days: 1)
            let bookingEmails = Set(mine.map(\.sourceID).filter { !$0.isEmpty })
            total += -transactions.filter { $0.isExpense && $0.date >= s.startOfDay && $0.date < e && !bookingEmails.contains($0.sourceID) }
                .reduce(0) { $0 + $1.amount }
        }
        return total
    }

    static func daysUntil(_ trip: Trip) -> Int? {
        trip.start.map { Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: $0.startOfDay).day ?? 0 }
    }

    static let basics = ["Passport", "Phone charger", "Power adapter", "Toothbrush", "Medication", "Headphones", "Cards and some cash"]

    private struct Packing: Decodable { let items: [String] }

    /// Asks Claude for a packing list for the trip; returns items not on the list yet.
    static func suggestPacking(for trip: Trip) async throws -> [String] {
        guard let claude = ClaudeClient() else { throw CloudError("This is part of Joshu Pro.") }
        let when = [trip.start, trip.end].compactMap { $0?.formatted(.dateTime.day().month(.wide).year()) }.joined(separator: " to ")
        let user = """
        Trip: \(trip.title). Destination: \(trip.destination.isEmpty ? "not set" : trip.destination). Dates: \(when.isEmpty ? "not set" : when)\(trip.nights.map { " (\($0) nights)" } ?? "").
        Notes: \(trip.notes.isEmpty ? "none" : trip.notes)
        Already on the list: \(trip.packing.joined(separator: ", "))
        """
        let system = """
        You make packing lists. Suggest 15-25 practical items for this trip, taking the destination's usual weather in that season and the trip length into account.
        Short item names (1-4 words), with quantities where useful ("3 T-shirts"). Skip anything already on the list. No categories or commentary.
        """
        let schema: [String: Any] = [
            "type": "object", "properties": ["items": ["type": "array", "items": ["type": "string"]]],
            "required": ["items"], "additionalProperties": false,
        ]
        let have = Set(trip.packing.map { $0.lowercased() })
        return try await claude.structured(Packing.self, system: system, user: user, schema: schema, effort: "low").items
            .filter { !have.contains($0.lowercased()) }
    }

    /// Starts a trip from a travel item on the bucket list.
    static func plan(from item: BucketItem, context: ModelContext) -> Trip {
        if item.uuid.isEmpty { item.uuid = UUID().uuidString.lowercased() }
        if let t = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).first(where: { $0.bucketUUID == item.uuid }) { return t }
        let t = Trip(title: item.title)
        t.uuid = UUID().uuidString.lowercased()
        t.bucketUUID = item.uuid
        t.start = item.targetDate
        t.notes = item.notes
        t.packing = basics
        context.insert(t)
        try? context.save()
        return t
    }
}
