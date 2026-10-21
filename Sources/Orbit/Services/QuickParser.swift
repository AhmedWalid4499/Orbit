import Foundation

/// Turns free text like "dentist thu 3pm #health" or "$12 lunch" into something to save.
struct QuickParser {
    enum Kind: Equatable { case task, event, expense, income, note, journal }

    struct Result {
        var kind: Kind
        var title: String
        var area: Area?
        var date: Date?
        var hasTime: Bool
        var amount: Double?
        var category: String?
        var priority: Int
        var durationMinutes: Int? = nil

        var summary: String {
            var parts: [String] = []
            switch kind {
            case .task: parts.append("Task")
            case .event: parts.append("Event")
            case .expense: parts.append("Expense")
            case .income: parts.append("Income")
            case .note: parts.append("Note")
            case .journal: parts.append("Journal")
            }
            if let amount { parts.append(Fmt.money(amount)) }
            if let date {
                parts.append(hasTime ? "\(Fmt.relativeDay(date)) \(Fmt.time(date))" : Fmt.relativeDay(date))
            }
            if let area { parts.append(area.title) }
            if priority > 0 { parts.append(String(repeating: "!", count: priority)) }
            return parts.joined(separator: " · ")
        }
    }

    static func parse(_ raw: String, now: Date = .now) -> Result {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Result(kind: .task, title: text, area: nil, date: nil, hasTime: false,
                            amount: nil, category: nil, priority: 0)

        // Prefixes
        for (prefix, kind) in [("note:", Kind.note), ("journal:", .journal)] where text.lowercased().hasPrefix(prefix) {
            result.kind = kind
            result.title = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return result
        }

        // #area tags
        if let match = text.range(of: #"#(\w+)"#, options: .regularExpression) {
            let tag = text[match].dropFirst().lowercased()
            if let area = Area.allCases.first(where: { $0.rawValue.hasPrefix(tag) }) {
                result.area = area
                text.removeSubrange(match)
            }
        }

        // Priority marks: "!!" or "!!!"
        if let match = text.range(of: #"(^|\s)(!{1,3})(?=\s|$)"#, options: .regularExpression) {
            result.priority = text[match].filter { $0 == "!" }.count
            text.removeSubrange(match)
        }

        // Money: "$12", "12.50$", "+500 salary", "€8"
        let moneyPattern = #"(^|\s)([+-]?)([$€£¥]|EGP|AED|SAR)?\s?(\d+(?:[.,]\d{1,2})?)\s?([$€£¥])?(?=\s|$)"#
        if let regex = try? NSRegularExpression(pattern: moneyPattern),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let signR = Range(m.range(at: 2), in: text),
           let numR = Range(m.range(at: 4), in: text),
           m.range(at: 3).location != NSNotFound || m.range(at: 5).location != NSNotFound || text[signR] == "+",
           let value = Double(text[numR].replacingOccurrences(of: ",", with: ".")) {
            let isIncome = text[signR] == "+"
            result.kind = isIncome ? .income : .expense
            result.amount = isIncome ? value : -value
            if let full = Range(m.range, in: text) { text.removeSubrange(full) }
            result.title = clean(text)
            result.category = isIncome ? "Income" : guessCategory(result.title)
            if result.area == nil { result.area = .money }
            return result
        }

        // Dates & times via the system date detector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let date = m.date, let r = Range(m.range, in: text) {
            let phrase = text[r].lowercased()
            result.hasTime = phrase.range(of: #"\d\s?(am|pm)|\d:\d|noon|midnight|\bat\s\d"#, options: .regularExpression) != nil
            result.date = result.hasTime ? date : date.startOfDay
            text.removeSubrange(r)
            text = text.replacingOccurrences(of: #"\s(on|at|by)\s*$"#, with: "", options: .regularExpression)
        }

        result.title = clean(text)
        if result.hasTime { result.kind = .event }
        return result
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func guessCategory(_ title: String) -> String {
        let t = title.lowercased()
        let map: [(String, [String])] = [
            ("Food", ["lunch", "dinner", "breakfast", "coffee", "grocer", "food", "restaurant", "snack"]),
            ("Transport", ["uber", "taxi", "fuel", "gas", "metro", "bus", "train", "careem", "parking"]),
            ("Bills", ["rent", "electric", "water", "internet", "phone", "bill"]),
            ("Subscriptions", ["netflix", "spotify", "icloud", "subscription", "youtube", "claude", "gym membership"]),
            ("Health", ["pharmacy", "doctor", "dentist", "gym", "medicine"]),
            ("Fun", ["cinema", "movie", "game", "concert", "bar"]),
            ("Shopping", ["amazon", "clothes", "shoes", "shop"]),
        ]
        return map.first { _, words in words.contains { t.contains($0) } }?.0 ?? "General"
    }
}
