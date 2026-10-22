import Foundation
import SwiftUI
import SwiftData
import Contacts

/// Keeps "last talked" current from Gmail, and imports people from macOS Contacts.
@MainActor
final class PeopleStore: ObservableObject {
    static let shared = PeopleStore()

    @Published private(set) var checking = false
    @AppStorage("peopleLastEmailCheck") private var lastCheck = 0.0

    func refreshIfDue(context: ModelContext) async {
        guard Date.now.timeIntervalSince1970 - lastCheck > 12 * 3600 else { return }
        await refreshLastContact(context: context)
    }

    /// For each person with an email address, finds the newest email between you and them in any connected inbox.
    func refreshLastContact(context: ModelContext) async {
        guard !checking, !Snapshot.isActive else { return }
        let accounts = InboxStore.shared.accounts
        let people = ((try? context.fetch(FetchDescriptor<Person>())) ?? []).filter { !$0.email.isEmpty }
        guard !accounts.isEmpty, !people.isEmpty else { return }
        checking = true
        defer { checking = false; lastCheck = Date.now.timeIntervalSince1970 }

        for account in accounts {
            guard let token = try? await GoogleAuth.accessToken(for: account) else { continue }
            for p in people {
                let addresses = p.email.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { $0.contains("@") }
                guard !addresses.isEmpty else { continue }
                let q = addresses.map { "from:\($0) OR to:\($0)" }.joined(separator: " OR ")
                var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
                comps.queryItems = [.init(name: "q", value: q), .init(name: "maxResults", value: "1")]
                guard let list = try? await gmailJSON(comps.url!, token: token),
                      let id = (list["messages"] as? [[String: Any]])?.first?["id"] as? String,
                      let msg = try? await gmailJSON(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=minimal")!, token: token),
                      let ms = Double(msg["internalDate"] as? String ?? "") else { continue }
                let date = Date(timeIntervalSince1970: ms / 1000)
                if (p.lastContact ?? .distantPast) < date {
                    p.lastContact = date
                    p.lastContactSource = "gmail"
                }
            }
        }
        try? context.save()
    }

    // MARK: Contacts

    struct ContactRow: Identifiable, Hashable {
        let id: String
        let name: String
        let email: String
        let phone: String
        let birthday: Date?
    }

    func loadContacts() async throws -> [ContactRow] {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else {
            throw CloudError("Allow Orbit to read Contacts in System Settings › Privacy & Security › Contacts.")
        }
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor,
                                       CNContactBirthdayKey as CNKeyDescriptor, CNContactIdentifierKey as CNKeyDescriptor]
        return try await Task.detached {
            var rows: [ContactRow] = []
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
                let name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
                guard !name.isEmpty else { return }
                var bday: Date?
                if var comps = c.birthday {
                    if comps.year == nil { comps.year = 1 } // year unknown
                    bday = Calendar(identifier: .gregorian).date(from: comps)
                }
                rows.append(ContactRow(id: c.identifier, name: name,
                                       email: c.emailAddresses.map { $0.value as String }.joined(separator: ", "),
                                       phone: c.phoneNumbers.first?.value.stringValue ?? "", birthday: bday))
            }
            return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }.value
    }

    func importContacts(_ rows: [ContactRow], context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var added = 0
        for r in rows {
            if let p = existing.first(where: { $0.name.caseInsensitiveCompare(r.name) == .orderedSame }) {
                if p.email.isEmpty { p.email = r.email }
                if p.phone.isEmpty { p.phone = r.phone }
                if p.birthday == nil { p.birthday = r.birthday }
                continue
            }
            let p = Person(name: r.name)
            p.email = r.email; p.phone = r.phone; p.birthday = r.birthday
            context.insert(p)
            added += 1
        }
        try? context.save()
        return added
    }
}
