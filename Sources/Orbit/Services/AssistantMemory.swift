import Foundation

/// Things the assistant remembers about you between chats ("vegetarian", "gym on Tuesdays", "prefers Zamalek").
/// Saved on this device, synced with your other settings, and listed in Settings › AI where you can edit them.
enum AssistantMemory {
    static let key = "assistant.memory"
    static let limit = 60

    static var items: [String] {
        get {
            guard let s = UserDefaults.standard.string(forKey: key), let d = s.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: d) else { return [] }
            return list
        }
        set {
            let clean = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if clean.isEmpty { UserDefaults.standard.removeObject(forKey: key); return }
            if let d = try? JSONEncoder().encode(Array(clean.suffix(limit))), let s = String(data: d, encoding: .utf8) {
                UserDefaults.standard.set(s, forKey: key)
            }
        }
    }

    /// Adds a fact, replacing a near-identical one. Returns false if it was already known.
    @discardableResult
    static func remember(_ fact: String) -> Bool {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return false }
        var list = items
        if list.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) { return false }
        list.append(f)
        items = list
        return true
    }

    /// Removes facts that contain `text` (case-insensitive). Returns what was removed.
    @discardableResult
    static func forget(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return [] }
        let gone = items.filter { $0.lowercased().contains(t) || t.contains($0.lowercased()) }
        items = items.filter { !gone.contains($0) }
        return gone
    }

    /// The block added to the assistant's instructions.
    static var promptBlock: String {
        let list = items
        guard !list.isEmpty else { return "" }
        return "\n\nWhat you remember about them (from earlier chats; use it naturally, don't recite it):\n" + list.map { "• \($0)" }.joined(separator: "\n")
    }
}
