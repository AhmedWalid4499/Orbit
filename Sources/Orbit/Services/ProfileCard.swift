import Foundation
import SwiftUI

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
            /// The service's real logo (nil for a website or other link).
            var brand: Brand? {
                switch self {
                case .linkedin: .linkedin
                case .github: .github
                case .instagram: .instagram
                case .x: .x
                case .youtube: .youtube
                case .tiktok: .tiktok
                case .facebook: .facebook
                case .behance: .behance
                case .dribbble: .dribbble
                case .calendly: .calendly
                case .whatsapp: .whatsapp
                case .website, .other: nil
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

        /// The short "who" under the service name: in/yourname, @yourname, or the website's address.
        var handle: String {
            let d = display
            let parts = d.split(separator: "/", maxSplits: 1).map(String.init)
            let path = parts.count > 1 ? parts[1] : ""
            switch kind {
            case .linkedin: return path.isEmpty ? d : path
            case .github, .x, .instagram, .tiktok, .youtube, .facebook, .behance, .dribbble:
                if d.hasPrefix("@") { return d }
                let last = path.split(separator: "/").last.map(String.init) ?? (parts.count == 1 && !d.contains(".") ? d : "")
                return last.isEmpty ? d : (last.hasPrefix("@") ? last : "@" + last)
            case .whatsapp: return value.trimmingCharacters(in: .whitespacesAndNewlines)
            default: return parts.first ?? d
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
    /// "photo": your photo fills the card (the colour becomes the accent); "color": a solid colour card.
    var style = "photo"
    /// What the QR code opens: "contact" (adds you to their contacts) or a link id.
    var qrTarget = "contact"
    /// Public web page: ahmedwalid4499.github.io/Orbit/card/?u=<slug>
    var publicSlug = ""
    var publishPublic = false
    /// Email and phone stay off the public page unless you turn this on.
    var publicShowContact = false

    init() {}

    // Older saved cards don't have every field; fill in defaults instead of failing.
    enum CodingKeys: String, CodingKey {
        case name, headline, company, email, phone, location, bio, links, colorIndex, showPhoto, qrTarget, style
        case publicSlug, publishPublic, publicShowContact
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        showPhoto = try c.decodeIfPresent(Bool.self, forKey: .showPhoto) ?? true
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "photo"
        qrTarget = try c.decodeIfPresent(String.self, forKey: .qrTarget) ?? "contact"
        publicSlug = try c.decodeIfPresent(String.self, forKey: .publicSlug) ?? ""
        publishPublic = try c.decodeIfPresent(Bool.self, forKey: .publishPublic) ?? false
        publicShowContact = try c.decodeIfPresent(Bool.self, forKey: .publicShowContact) ?? false
    }

    static let colors: [Color] = [Theme.lime, Theme.pink, Theme.cyan, Theme.purple, Theme.orange, Theme.mint, Color(hex: 0x141416)]
    var color: Color { Self.colors[min(max(colorIndex, 0), Self.colors.count - 1)] }
    var isDark: Bool { colorIndex == Self.colors.count - 1 }

    var filledLinks: [Link] { links.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    // MARK: Storage

    static func load() -> ProfileCard {
        if let s = UserDefaults.standard.string(forKey: "profileCard"), let data = s.data(using: .utf8),
           let card = try? JSONDecoder().decode(ProfileCard.self, from: data) { return card }
        var card = ProfileCard()
        card.name = Platform.userName
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

    static let webBase = "https://ahmedwalid4499.github.io/Orbit/card/?u="
    static func isValidSlug(_ s: String) -> Bool { s.range(of: #"^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$"#, options: .regularExpression) != nil }
    var publicURL: String? { publishPublic && Self.isValidSlug(publicSlug) ? Self.webBase + publicSlug : nil }

    /// "Sara Hassan" → "sara-hassan"
    static func slugify(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let dashed = folded.map { $0.isLetter && $0.isASCII || $0.isNumber ? String($0) : "-" }.joined()
        return String(dashed.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
    }

    /// What the public page shows (email and phone only if you chose to).
    func publicData(photo: PlatformImage?) -> [String: Any] {
        var d: [String: Any] = ["name": name, "headline": headline, "company": company, "location": location, "bio": bio,
                                "colorIndex": colorIndex, "style": style, "cover": "",
                                "links": filledLinks.map { ["kind": $0.kind.rawValue, "url": $0.url, "display": $0.display, "title": $0.kind.title, "handle": $0.handle] },
                                "email": publicShowContact ? email : "", "phone": publicShowContact ? phone : "", "photo": ""]
        if showPhoto, let photo, let jpeg = photo.square(side: 200, type: .jpeg, quality: 0.7) {
            d["photo"] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
        if style == "photo", showPhoto, let cover = CardPhoto.image ?? photo, let jpeg = cover.jpeg(maxSide: 900, quality: 0.72) {
            d["cover"] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
        return d
    }

    /// What the QR code holds.
    var qrPayload: String {
        if qrTarget == "web", let url = publicURL { return url }
        if qrTarget != "contact", let l = filledLinks.first(where: { $0.id.uuidString == qrTarget }) { return l.url }
        return vCard
    }

    var shareText: String {
        ([name, [headline, company].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }
         + [email, phone].filter { !$0.isEmpty }
         + filledLinks.map { "\($0.kind.title): \($0.url)" }).joined(separator: "\n")
    }
}

/// The card's background photo, kept sharper than the 512 px profile photo and synced between devices
/// (UserDefaults "cardPhoto", a JPEG in base64). Without one, the card uses the profile photo.
enum CardPhoto {
    static let key = "cardPhoto"
    private static var cached: (String, PlatformImage)?

    static var image: PlatformImage? {
        guard let s = UserDefaults.standard.string(forKey: key), !s.isEmpty else { return nil }
        if let cached, cached.0 == s { return cached.1 }
        guard let data = Data(base64Encoded: s), let img = PlatformImage(data: data) else { return nil }
        cached = (s, img)
        return img
    }

    static func set(_ image: PlatformImage) {
        guard let jpeg = image.jpeg(maxSide: 1400, quality: 0.8) else { return }
        UserDefaults.standard.set(jpeg.base64EncodedString(), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Your card as one small, self-contained web page (photo, links with their logos, Save contact), made every time
/// the card is shared or saved. It works offline and can be opened, emailed or hosted anywhere.
enum CardHTML {
    static func page(_ card: ProfileCard, photo: PlatformImage?) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let accent = card.isDark ? "#EDAA2F" : (card.color.hexString ?? "#E6FF1F")
        let img = (card.showPhoto ? (CardPhoto.image ?? photo) : nil)?.jpeg(maxSide: 900, quality: 0.78).map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let role = [card.headline, card.company].filter { !$0.isEmpty }.joined(separator: " · ")
        let vcf = "data:text/vcard;charset=utf-8," + (card.vCard.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        func icon(_ brand: Brand?) -> String {
            guard let brand, !brand.path.isEmpty else {
                return ##"<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>"##
            }
            let hex = String(format: "#%06X", brand.hex)
            return ##"<svg viewBox="0 0 24 24" class="b" style="background:\##(hex)"><path fill="#fff" transform="translate(4.2 4.2) scale(.65)" d="\##(brand.path)"/></svg>"##
        }
        var rows = ""
        if !card.email.isEmpty {
            rows += ##"<a href="mailto:\##(esc(card.email))"><svg viewBox="0 0 24 24"><path fill="currentColor" d="M3 5h18a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zm9 7 8.5-5.5h-17z"/></svg><span><b>Email</b><i>\##(esc(card.email))</i></span></a>"##
        }
        if !card.phone.isEmpty {
            rows += ##"<a href="tel:\##(esc(card.phone.filter { $0.isNumber || $0 == "+" }))"><svg viewBox="0 0 24 24"><path fill="currentColor" d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25 11.4 11.4 0 0 0 3.6.57 1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1z"/></svg><span><b>Call</b><i>\##(esc(card.phone))</i></span></a>"##
        }
        for l in card.filledLinks {
            let title = l.kind == .other ? (l.handle.isEmpty ? "Link" : l.handle) : l.kind.title
            rows += ##"<a href="\##(esc(l.url))" target="_blank" rel="noopener">\##(icon(l.kind.brand))<span><b>\##(esc(title))</b><i>\##(esc(l.kind == .other ? l.display : l.handle))</i></span></a>"##
        }
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(card.name.isEmpty ? "My card" : card.name))</title>
        <style>
        *{box-sizing:border-box;margin:0}
        body{font:16px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0b0b0c;color:#fff;min-height:100vh;display:grid;place-items:center;padding:24px}
        .card{width:100%;max-width:420px;border-radius:32px;overflow:hidden;background:#111113;box-shadow:0 30px 80px rgba(0,0,0,.5)}
        .hero{position:relative;height:\(img == nil ? "160px" : "380px");background:\(img.map { "url(\($0)) center/cover" } ?? accent)}
        .hero:after{content:"";position:absolute;inset:0;background:linear-gradient(to bottom,transparent 45%,#111113)}
        .body{padding:0 26px 26px;margin-top:-70px;position:relative}
        h1{font:700 34px/1.05 ui-serif,Georgia,serif;letter-spacing:-.01em}
        .role{opacity:.82;margin-top:6px}.bio{opacity:.9;font-size:14px;margin-top:10px}
        .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:\(accent);margin-left:6px;vertical-align:middle}
        .links{display:grid;gap:8px;margin-top:20px}
        .links a{display:flex;align-items:center;gap:12px;padding:10px 12px;border-radius:16px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.1);color:#fff;text-decoration:none}
        .links a:hover{background:rgba(255,255,255,.12)}
        .links svg{width:30px;height:30px;flex:none;color:\(accent)}
        .links svg.b{border-radius:8px}
        .links span{display:flex;flex-direction:column;min-width:0}
        .links b{font-size:14px}.links i{font-style:normal;font-size:12px;opacity:.6;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        .save{display:block;margin-top:16px;text-align:center;padding:13px;border-radius:999px;background:\(accent);color:#111;font-weight:700;text-decoration:none}
        footer{text-align:center;font-size:11px;opacity:.4;margin-top:14px}
        </style></head>
        <body><div class="card">
        <div class="hero"></div>
        <div class="body">
        <h1>\(esc(card.name))<span class="dot"></span></h1>
        \(role.isEmpty ? "" : "<p class=\"role\">\(esc(role))</p>")
        \(card.location.isEmpty ? "" : "<p class=\"role\" style=\"font-size:13px\">\(esc(card.location))</p>")
        \(card.bio.isEmpty ? "" : "<p class=\"bio\">\(esc(card.bio))</p>")
        <div class="links">\(rows)</div>
        <a class="save" href="\(vcf)" download="\(esc(card.name.isEmpty ? "contact" : card.name)).vcf">Save contact</a>
        <footer>Made with Orbit</footer>
        </div></div></body></html>
        """
    }
}
