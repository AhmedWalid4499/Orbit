import Foundation
import SwiftUI

/// Lists shared with other Orbit users (groceries, a trip plan). They live in Supabase's `shared_lists` table
/// (supabase/shared_lists.sql), not in the local database: everyone on a list reads and writes the same row.
/// You share a list by its six-letter code; whoever joins with the code can see and edit it.
struct SharedList: Identifiable, Equatable {
    var id: String
    var code: String
    var title: String
    var ownerID: String
    var memberCount: Int
    var items: [Item]
    var updatedAt: Date?

    struct Item: Identifiable, Equatable {
        var id: String
        var text: String
        var done: Bool
        /// First name of whoever added it.
        var by: String
        var at: Date?

        var json: [String: Any] {
            ["id": id, "text": text, "done": done, "by": by, "at": at.map { J.date($0) } ?? NSNull()]
        }
        init(id: String = UUID().uuidString.lowercased(), text: String, done: Bool = false, by: String = "", at: Date? = .now) {
            self.id = id; self.text = text; self.done = done; self.by = by; self.at = at
        }
        init?(_ d: [String: Any]) {
            guard let id = d["id"] as? String else { return nil }
            self.init(id: id, text: J.str(d["text"]), done: J.bool(d["done"]), by: J.str(d["by"]), at: J.date(d["at"]))
        }
    }

    @MainActor var isMine: Bool { ownerID == CloudAuth.session?.userID }
    var openCount: Int { items.filter { !$0.done }.count }

    var inviteText: String {
        "Join my Orbit list “\(title)”: in Orbit open Tasks › Shared lists › Join and enter \(code)."
    }
}

@MainActor
final class SharedListStore: ObservableObject {
    static let shared = SharedListStore()

    @Published private(set) var lists: [SharedList] = Snapshot.isDemo ? SharedListStore.demo : []
    @Published private(set) var loading = false
    @Published var error: String?

    static var me: String { Platform.userName.split(separator: " ").first.map(String.init) ?? "" }
    var isAvailable: Bool { CloudSync.shared.isSignedIn || Snapshot.isDemo }

    private var base: String { "\(SupabaseConfig.url)/rest/v1" }

    func refresh() async {
        if Snapshot.isDemo { if lists.isEmpty { lists = Self.demo }; return }
        guard CloudSync.shared.isSignedIn else { lists = []; return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await call("\(base)/shared_lists?select=id,code,title,owner,members,items,updated_at&order=updated_at.desc", "GET") as? [[String: Any]] ?? []
            lists = rows.compactMap(Self.parse)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func create(_ title: String) async -> SharedList? {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if Snapshot.isDemo {
            let l = SharedList(id: UUID().uuidString, code: "DEMO42", title: t, ownerID: "", memberCount: 1, items: [], updatedAt: .now)
            lists.insert(l, at: 0); return l
        }
        do {
            let rows = try await call("\(base)/shared_lists?select=id,code,title,owner,members,items,updated_at", "POST",
                                      body: [["title": t]], prefer: "return=representation") as? [[String: Any]] ?? []
            guard let l = rows.first.flatMap(Self.parse) else { return nil }
            lists.insert(l, at: 0)
            return l
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Joins someone else's list by its code.
    func join(code: String) async -> Bool {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.count >= 4 else { error = "Enter the code from the invite."; return false }
        do {
            let id = try await call("\(base)/rpc/join_shared_list", "POST", body: ["p_code": c])
            guard id is String else { error = "No list has the code \(c)."; return false }
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription.contains("not found") ? "No list has the code \(c)." : error.localizedDescription
            return false
        }
    }

    func put(_ item: SharedList.Item, in list: SharedList) async {
        update(list.id) { l in
            if let i = l.items.firstIndex(where: { $0.id == item.id }) { l.items[i] = item } else { l.items.append(item) }
        }
        guard !Snapshot.isDemo else { return }
        await rpc("shared_list_put_item", ["p_list": list.id, "p_item": item.json])
    }

    func remove(_ item: SharedList.Item, from list: SharedList) async {
        update(list.id) { $0.items.removeAll { $0.id == item.id } }
        guard !Snapshot.isDemo else { return }
        await rpc("shared_list_remove_item", ["p_list": list.id, "p_id": item.id])
    }

    func clearDone(_ list: SharedList) async {
        for item in list.items where item.done { await remove(item, from: list) }
    }

    func rename(_ list: SharedList, to title: String) async {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        update(list.id) { $0.title = t }
        guard !Snapshot.isDemo else { return }
        _ = try? await call("\(base)/shared_lists?id=eq.\(list.id)", "PATCH", body: ["title": t], prefer: "return=minimal")
    }

    /// Leaves the list. The owner leaving deletes it for everyone.
    func leave(_ list: SharedList) async {
        lists.removeAll { $0.id == list.id }
        guard !Snapshot.isDemo else { return }
        await rpc("leave_shared_list", ["p_list": list.id])
    }

    // MARK: Plumbing

    private func update(_ id: String, _ change: (inout SharedList) -> Void) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        change(&lists[i])
    }

    private func rpc(_ name: String, _ body: [String: Any]) async {
        do { _ = try await call("\(base)/rpc/\(name)", "POST", body: body) }
        catch { self.error = error.localizedDescription }
    }

    private func call(_ url: String, _ method: String, body: Any? = nil, prefer: String? = nil) async throws -> Any? {
        guard let u = URL(string: url) else { return nil }
        do {
            return try await CloudSync.shared.rest(u, method: method, body: body, prefer: prefer)
        } catch let e as CloudError where e.message.contains("404") || e.message.contains("shared_list") || e.message.contains("aren't set up") {
            throw CloudError("Shared lists need a one-time setup: run supabase/shared_lists.sql in Supabase › SQL Editor.")
        }
    }

    private static func parse(_ r: [String: Any]) -> SharedList? {
        guard let id = r["id"] as? String else { return nil }
        let items = (r["items"] as? [[String: Any]] ?? []).compactMap(SharedList.Item.init)
        return SharedList(id: id, code: J.str(r["code"]), title: J.str(r["title"]), ownerID: J.str(r["owner"]),
                          memberCount: (r["members"] as? [Any])?.count ?? 1, items: items, updatedAt: J.date(r["updated_at"]))
    }

    static let demo: [SharedList] = [
        SharedList(id: "demo-groceries", code: "K7Q2MX", title: "Groceries", ownerID: "", memberCount: 2, items: [
            .init(text: "Eggs", by: "Alex"), .init(text: "Tomatoes and cucumbers", by: "Sara"),
            .init(text: "Greek yogurt", by: "Sara"), .init(text: "Coffee beans", done: true, by: "Alex"),
        ], updatedAt: .now),
        SharedList(id: "demo-dahab", code: "D4HB9T", title: "Dahab weekend", ownerID: "", memberCount: 3, items: [
            .init(text: "Book the bus", done: true, by: "Omar"), .init(text: "Snorkel gear", by: "Alex"),
            .init(text: "Sunscreen", by: "Sara"),
        ], updatedAt: .now),
    ]
}
