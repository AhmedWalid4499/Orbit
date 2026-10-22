import Foundation
import SwiftUI
import AppKit

/// Your shareable contact card: name, headline, contact details and social links.
/// Stored as JSON in the "profileCard" setting, so it syncs with your Orbit account.
struct ProfileCard: Codable, Equatable {
    struct Link: Codable, Equatable, Identifiable {
        var id = UUID()
        var kind: Kind
        var value: String

        enum Kind: String, Codable, CaseIterable, Identifiable {
            case linkedin, website, github, instagram, x, youtube, tiktok, facebook, behance, dribbble, calendly, whatsapp, other
            var id: String { rawValue }
            var title: String {
                switch self {
                case .linkedin: "LinkedIn"
                case .x: "X (Twitter)"
                case .github: "GitHub"
                case .youtube: "YouTube"
                case .tiktok: "TikTok"
                case .whatsapp: "WhatsApp"
                default: rawValue.capitalized
                }
            }
            var symbol: String {
                switch self {
                case .linkedin: "briefcase.fill"
                case .website: "globe"
                case .github: "chevron.left.forwardslash.chevron.right"
                case .instagram: "camera.fill"
                case .x: "at"
                case .youtube: "play.rectangle.fill"
                case .tiktok: "music.note"
                case .facebook: "person.2.fill"
                case .behance, .dribbble: "paintpalette.fill"
                case .calendly: "calendar"
                case .whatsapp: "message.fill"
                case .other: "link"
                }
            }
            var placeholder: String {
                switch self {
                case .linkedin: "linkedin.com/in/yourname"
                case .website: "yourname.com"
                case .github: "github.com/yourname"
                case .instagram: "@yourname"
                case .x: "@yourname"
                case .youtube: "youtube.com/@yourname"
                case .tiktok: "@yourname"
                case .facebook: "facebook.com/yourname"
                case .behance: "behance.net/yourname"
                case .dribbble: "dribbble.com/yourname"
                case .calendly: "calendly.com/yourname"
                case .whatsapp: "+20 100 000 0000"
                case .other: "https://…"
                }
            }
        }

        /// A full URL for the link: handles "@name" and bare domains.
        var url: String {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.lowercased().hasPrefix("http") { return v }
            let handle = v.hasPrefix("@") ? String(v.dropFirst()) : v
            let isHandle = v.hasPrefix("@") || !v.contains(".")
            switch kind {
            case .instagram where isHandle: return "https://instagram.com/\(handle)"
            case .x where isHandle: return "https://x.com/\(handle)"
            case .tiktok where isHandle: return "https://tiktok.com/@\(handle)"
            case .github where isHandle: return "https://github.com/\(handle)"
            case .linkedin where isHandle: return "https://linkedin.com/in/\(handle)"
            case .youtube where isHandle: return "https://youtube.com/@\(handle)"
            case .whatsapp: return "https://wa.me/\(v.filter(\.isNumber))"
            default: return "https://\(v)"
            }
        }

        /// Short text shown on the card (no https://, no trailing slash).
        var display: String {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    var name = ""
    var headline = ""
    var company = ""
    var email = ""
    var phone = ""
    var location = ""
    var bio = ""
    var links: [Link] = []
    /// Index into the card colours.
    var colorIndex = 0
    var showPhoto = true
    /// What the QR code opens: "contact" (adds you to their contacts) or a link id.
    var qrTarget = "contact"

    static let colors: [Color] = [Theme.lime, Theme.pink, Theme.cyan, Theme.purple, Theme.orange, Theme.mint, Color(hex: 0x141416)]
    var color: Color { Self.colors[min(max(colorIndex, 0), Self.colors.count - 1)] }
    var isDark: Bool { colorIndex == Self.colors.count - 1 }

    var filledLinks: [Link] { links.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty } }

    // MARK: Storage

    static func load() -> ProfileCard {
        if let s = UserDefaults.standard.string(forKey: "profileCard"), let data = s.data(using: .utf8),
           let card = try? JSONDecoder().decode(ProfileCard.self, from: data) { return card }
        var card = ProfileCard()
        card.name = UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()
        card.links = [Link(kind: .linkedin, value: ""), Link(kind: .website, value: "")]
        return card
    }

    func save() {
        if let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "profileCard")
        }
    }

    // MARK: Contact file

    /// vCard 3.0, so anyone can add you to their contacts with all your links.
    var vCard: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
        }
        let parts = name.split(separator: " ")
        let last = parts.count > 1 ? String(parts.last!) : ""
        let first = parts.count > 1 ? parts.dropLast().joined(separator: " ") : name
        var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:\(esc(last));\(esc(first));;;", "FN:\(esc(name))"]
        if !headline.isEmpty { lines.append("TITLE:\(esc(headline))") }
        if !company.isEmpty { lines.append("ORG:\(esc(company))") }
        if !email.isEmpty { lines.append("EMAIL;TYPE=INTERNET:\(email)") }
        if !phone.isEmpty { lines.append("TEL;TYPE=CELL:\(phone)") }
        if !location.isEmpty { lines.append("ADR;TYPE=HOME:;;;\(esc(location));;;") }
        for l in filledLinks {
            switch l.kind {
            case .linkedin, .x, .instagram, .facebook, .tiktok, .github, .youtube:
                lines.append("X-SOCIALPROFILE;TYPE=\(l.kind.rawValue):\(l.url)")
                lines.append("URL;TYPE=\(l.kind.title):\(l.url)")
            default:
                lines.append("URL;TYPE=\(l.kind.title):\(l.url)")
            }
        }
        if !bio.isEmpty { lines.append("NOTE:\(esc(bio))") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    /// What the QR code holds.
    var qrPayload: String {
        if qrTarget != "contact", let l = filledLinks.first(where: { $0.id.uuidString == qrTarget }) { return l.url }
        return vCard
    }

    var shareText: String {
        ([name, [headline, company].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }
         + [email, phone].filter { !$0.isEmpty }
         + filledLinks.map { "\($0.kind.title): \($0.url)" }).joined(separator: "\n")
    }
}
