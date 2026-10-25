import Foundation
import SwiftUI
import SwiftData
import CryptoKit

// MARK: - Supabase project

/// Project URL and publishable key, from Supabase.json inside the app (Support/Supabase.json in the repo).
/// The publishable key is meant to ship in apps; Row Level Security keeps each person's rows private.
enum SupabaseConfig {
    private static let file: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Supabase", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return json
    }()
    /// ORBIT_SUPABASE_URL points a test run at a local stand-in server.
    static var url: String { ProcessInfo.processInfo.environment["ORBIT_SUPABASE_URL"] ?? file["url"] ?? "" }
    static var key: String { file["key"] ?? "" }
    static var isConfigured: Bool { !url.isEmpty && !key.isEmpty }
}

struct CloudError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

// MARK: - Account (Supabase Auth, email + password)

struct CloudSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

@MainActor
enum CloudAuth {
    static var session: CloudSession? {
        get { Keychain.read("supabase-session").flatMap { try? JSONDecoder().decode(CloudSession.self, from: Data($0.utf8)) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue), let s = String(data: data, encoding: .utf8) {
                Keychain.write(s, account: "supabase-session")
            } else {
                Keychain.delete("supabase-session")
            }
        }
    }

    enum SignUpResult { case signedIn, checkEmail }

    static func signUp(email: String, password: String) async throws -> SignUpResult {
        let json = try await auth("signup", body: ["email": email, "password": password])
        if let s = parseSession(json) { session = s; return .signedIn }
        return .checkEmail // email confirmation is on: they confirm, then sign in
    }

    static func signIn(email: String, password: String) async throws {
        let json = try await auth("token?grant_type=password", body: ["email": email, "password": password])
        guard let s = parseSession(json) else { throw CloudError("Sign-in failed.") }
        session = s
    }

    // MARK: Sign in with Google (Supabase OAuth, PKCE)

    static let callbackURL = "com.personal.orbit://auth-callback"
    private static var pending: (verifier: String, continuation: CheckedContinuation<Void, Error>)?

    /// Opens Google in the browser; Supabase sends the browser back to Orbit with a one-time code.
    /// The same Google account signs in to the same Orbit account on any device, and is linked
    /// automatically to an email/password account with the same address.
    static func signInWithGoogle() async throws {
        guard SupabaseConfig.isConfigured else { throw CloudError("Sync isn't set up in this copy of Orbit.") }
        pending?.continuation.resume(throwing: CancellationError())
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(string: "\(SupabaseConfig.url)/auth/v1/authorize")!
        comps.queryItems = [.init(name: "provider", value: "google"), .init(name: "redirect_to", value: callbackURL),
                            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "s256")]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pending = (verifier, cont)
            Task { @MainActor in
                // The sign-in window hands the redirect straight back (no reliance on which app owns the link scheme).
                if let back = await Platform.webAuth(comps.url!, callbackScheme: "com.personal.orbit") { handleCallback(back) }
                else if let p = pending { pending = nil; p.continuation.resume(throwing: CloudError("Google sign-in was cancelled.")) }
            }
        }
    }

    /// Called when the browser hands control back to Orbit.
    static func handleCallback(_ url: URL) {
        guard url.absoluteString.hasPrefix(callbackURL), let p = pending else { return }
        pending = nil
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fragment = URLComponents(string: "x://x?" + (url.fragment ?? ""))?.queryItems ?? []
        func value(_ k: String) -> String? { (items + fragment).first { $0.name == k }?.value }
        if let code = value("code") {
            Task {
                do {
                    let json = try await auth("token?grant_type=pkce", body: ["auth_code": code, "code_verifier": p.verifier])
                    guard let s = parseSession(json) else { throw CloudError("Google sign-in didn't finish.") }
                    session = s
                    Platform.bringToFront()
                    p.continuation.resume()
                } catch {
                    p.continuation.resume(throwing: error)
                }
            }
        } else {
            let message = value("error_description")?.replacingOccurrences(of: "+", with: " ") ?? "Google sign-in was cancelled."
            p.continuation.resume(throwing: CloudError(message))
        }
    }

    static func signOut() {
        if let token = session?.accessToken {
            var req = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/logout")!)
            req.httpMethod = "POST"
            req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req).resume()
        }
        session = nil
    }

    static func resetPassword(email: String) async throws {
        _ = try await auth("recover", body: ["email": email])
    }

    /// A valid access token, refreshing it when it's about to expire.
    static func accessToken() async throws -> String {
        guard var s = session else { throw CloudError("Not signed in.") }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        let json = try await auth("token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
        guard let fresh = parseSession(json) else { session = nil; throw CloudError("Your Orbit sign-in expired. Sign in again in Settings › Account.") }
        s = fresh
        session = s
        return s.accessToken
    }

    private static func auth(_ path: String, body: [String: String]) async throws -> [String: Any] {
        guard SupabaseConfig.isConfigured else { throw CloudError("Sync isn't set up in this copy of Orbit.") }
        var req = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = json["msg"] as? String ?? json["error_description"] as? String ?? json["message"] as? String ?? "Error \(status)"
            throw CloudError(msg)
        }
        return json
    }

    private static func parseSession(_ json: [String: Any]) -> CloudSession? {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let expires = (json["expires_in"] as? Double) ?? 3600
        return CloudSession(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires),
                            userID: id, email: user["email"] as? String ?? "")
    }
}

// MARK: - What gets synced

/// Turns each kind of item into JSON for the `orbit_records` table and back.
@MainActor
private struct SyncKind {
    let kind: String
    let fetch: (ModelContext) -> [any PersistentModel]
    let uuid: (any PersistentModel) -> String
    let encode: (any PersistentModel) -> [String: Any]
    let apply: ([String: Any], any PersistentModel) -> Void
    let make: (ModelContext) -> any PersistentModel
}

enum J {
    static let iso = ISO8601DateFormatter()
    static func date(_ d: Date?) -> Any { d.map { iso.string(from: $0) } ?? NSNull() }
    static func date(_ v: Any?) -> Date? { (v as? String).flatMap { iso.date(from: $0) } }
    static func str(_ v: Any?) -> String { v as? String ?? "" }
    static func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
    static func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }
    static func strings(_ v: Any?) -> [String] { v as? [String] ?? [] }
}

@MainActor
private let syncKinds: [SyncKind] = [
    SyncKind(kind: "task",
             fetch: { (try? $0.fetch(FetchDescriptor<TaskItem>())) ?? [] }, uuid: { ($0 as! TaskItem).uuid },
             encode: { m in let t = m as! TaskItem
                 return ["title": t.title, "notes": t.notes, "area": t.areaRaw, "due": J.date(t.due), "priority": t.priority,
                         "isDone": t.isDone, "completedAt": J.date(t.completedAt), "createdAt": J.date(t.createdAt), "repeat": t.recurrenceRaw,
                         "remindAt": J.date(t.remindAt),
                         "place": ["name": t.placeName, "lat": t.placeLat, "lon": t.placeLon, "onLeave": t.placeOnLeave]] },
             apply: { d, m in let t = m as! TaskItem
                 t.title = J.str(d["title"]); t.notes = J.str(d["notes"]); t.areaRaw = J.str(d["area"]); t.due = J.date(d["due"])
                 t.priority = J.int(d["priority"]); t.isDone = J.bool(d["isDone"]); t.completedAt = J.date(d["completedAt"])
                 t.createdAt = J.date(d["createdAt"]) ?? t.createdAt; t.recurrenceRaw = J.str(d["repeat"]).isEmpty ? "none" : J.str(d["repeat"])
                 // Only rows from an Orbit that knows reminders carry these (the Windows app doesn't yet).
                 if d["remindAt"] != nil { t.remindAt = J.date(d["remindAt"]) }
                 if let p = d["place"] as? [String: Any] {
                     t.placeName = J.str(p["name"]); t.placeLat = J.num(p["lat"]); t.placeLon = J.num(p["lon"]); t.placeOnLeave = J.bool(p["onLeave"])
                 } },
             make: { let t = TaskItem(title: ""); $0.insert(t); return t }),
    SyncKind(kind: "event",
             fetch: { (try? $0.fetch(FetchDescriptor<EventItem>())) ?? [] }, uuid: { ($0 as! EventItem).uuid },
             encode: { m in let e = m as! EventItem
                 return ["title": e.title, "start": J.date(e.start), "end": J.date(e.end), "area": e.areaRaw, "location": e.location, "notes": e.notes] },
             apply: { d, m in let e = m as! EventItem
                 e.title = J.str(d["title"]); e.start = J.date(d["start"]) ?? e.start; e.end = J.date(d["end"]) ?? e.end
                 e.areaRaw = J.str(d["area"]); e.location = J.str(d["location"]); e.notes = J.str(d["notes"]) },
             make: { let e = EventItem(title: "", start: .now, end: .now); $0.insert(e); return e }),
    SyncKind(kind: "habit",
             fetch: { (try? $0.fetch(FetchDescriptor<Habit>())) ?? [] }, uuid: { ($0 as! Habit).uuid },
             encode: { m in let h = m as! Habit
                 return ["name": h.name, "symbol": h.symbol, "area": h.areaRaw, "targetPerWeek": h.targetPerWeek,
                         "createdAt": J.date(h.createdAt), "doneDays": h.doneDays.sorted()] },
             apply: { d, m in let h = m as! Habit
                 h.name = J.str(d["name"]); h.symbol = J.str(d["symbol"]); h.areaRaw = J.str(d["area"])
                 h.targetPerWeek = J.int(d["targetPerWeek"]); h.createdAt = J.date(d["createdAt"]) ?? h.createdAt; h.doneDays = J.strings(d["doneDays"]) },
             make: { let h = Habit(name: ""); $0.insert(h); return h }),
    SyncKind(kind: "transaction",
             fetch: { (try? $0.fetch(FetchDescriptor<Transaction>())) ?? [] }, uuid: { ($0 as! Transaction).uuid },
             encode: { m in let t = m as! Transaction
                 return ["title": t.title, "amount": t.amount, "category": t.category, "date": J.date(t.date), "isRecurring": t.isRecurring,
                         "source": t.source, "sourceID": t.sourceID, "originalAmount": t.originalAmount, "originalCurrency": t.originalCurrency,
                         "account": t.account] },
             apply: { d, m in let t = m as! Transaction
                 t.title = J.str(d["title"]); t.amount = J.num(d["amount"]); t.category = J.str(d["category"]); t.date = J.date(d["date"]) ?? t.date
                 t.isRecurring = J.bool(d["isRecurring"]); t.source = J.str(d["source"]); t.sourceID = J.str(d["sourceID"])
                 t.originalAmount = J.num(d["originalAmount"]); t.originalCurrency = J.str(d["originalCurrency"]); t.account = J.str(d["account"]) },
             make: { let t = Transaction(title: "", amount: 0); $0.insert(t); return t }),
    SyncKind(kind: "note",
             fetch: { (try? $0.fetch(FetchDescriptor<Note>())) ?? [] }, uuid: { ($0 as! Note).uuid },
             encode: { m in let n = m as! Note
                 return ["title": n.title, "body": n.body, "createdAt": J.date(n.createdAt), "updatedAt": J.date(n.updatedAt),
                         "isJournal": n.isJournal, "pinned": n.pinned, "mood": n.mood, "moodSetByUser": n.moodSetByUser,
                         "chat": n.chatData?.base64EncodedString() ?? NSNull()] },
             apply: { d, m in let n = m as! Note
                 n.title = J.str(d["title"]); n.body = J.str(d["body"]); n.createdAt = J.date(d["createdAt"]) ?? n.createdAt
                 n.updatedAt = J.date(d["updatedAt"]) ?? n.updatedAt; n.isJournal = J.bool(d["isJournal"]); n.pinned = J.bool(d["pinned"])
                 n.mood = J.int(d["mood"]); n.moodSetByUser = J.bool(d["moodSetByUser"]); n.chatData = (d["chat"] as? String).flatMap { Data(base64Encoded: $0) } },
             make: { let n = Note(title: ""); $0.insert(n); return n }),
    SyncKind(kind: "book",
             fetch: { (try? $0.fetch(FetchDescriptor<Book>())) ?? [] }, uuid: { ($0 as! Book).uuid },
             encode: { m in let b = m as! Book
                 return ["title": b.title, "author": b.author, "status": b.statusRaw, "rating": b.rating, "categories": b.categories,
                         "notes": b.notes, "coverURL": b.coverURL, "isbn": b.isbn, "pageCount": b.pageCount, "progress": b.progress,
                         "year": b.year, "addedAt": J.date(b.addedAt), "startedAt": J.date(b.startedAt), "finishedAt": J.date(b.finishedAt),
                         "source": b.source, "sources": b.sources, "externalID": b.externalID] },
             apply: { d, m in let b = m as! Book
                 b.title = J.str(d["title"]); b.author = J.str(d["author"]); b.statusRaw = J.str(d["status"]); b.rating = J.int(d["rating"])
                 b.categories = J.strings(d["categories"]); b.notes = J.str(d["notes"]); b.coverURL = J.str(d["coverURL"]); b.isbn = J.str(d["isbn"])
                 b.pageCount = J.int(d["pageCount"]); b.progress = J.num(d["progress"]); b.year = J.int(d["year"])
                 b.addedAt = J.date(d["addedAt"]) ?? b.addedAt; b.startedAt = J.date(d["startedAt"]); b.finishedAt = J.date(d["finishedAt"])
                 b.source = J.str(d["source"]); b.sources = J.strings(d["sources"]); b.externalID = J.str(d["externalID"]) },
             make: { let b = Book(title: "", author: ""); $0.insert(b); return b }),
    SyncKind(kind: "bookCategory",
             fetch: { (try? $0.fetch(FetchDescriptor<BookCategory>())) ?? [] }, uuid: { ($0 as! BookCategory).uuid },
             encode: { m in let c = m as! BookCategory
                 return ["name": c.name, "colorIndex": c.colorIndex, "symbol": c.symbol, "createdAt": J.date(c.createdAt)] },
             apply: { d, m in let c = m as! BookCategory
                 c.name = J.str(d["name"]); c.colorIndex = J.int(d["colorIndex"]); c.symbol = J.str(d["symbol"]); c.createdAt = J.date(d["createdAt"]) ?? c.createdAt },
             make: { let c = BookCategory(name: "", colorIndex: 0); $0.insert(c); return c }),
    SyncKind(kind: "bucket",
             fetch: { (try? $0.fetch(FetchDescriptor<BucketItem>())) ?? [] }, uuid: { ($0 as! BucketItem).uuid },
             encode: { m in let b = m as! BucketItem
                 return ["title": b.title, "notes": b.notes, "kind": b.kindRaw, "targetDate": J.date(b.targetDate), "excitement": b.excitement,
                         "isDone": b.isDone, "doneAt": J.date(b.doneAt), "createdAt": J.date(b.createdAt),
                         "place": ["category": b.placeCategoryRaw, "address": b.address, "lat": b.latitude, "lon": b.longitude, "url": b.mapURL]] },
             apply: { d, m in let b = m as! BucketItem
                 // Only rows written by an Orbit that knows places carry them (the Windows app doesn't yet).
                 if let p = d["place"] as? [String: Any] {
                     b.placeCategoryRaw = J.str(p["category"]); b.address = J.str(p["address"]); b.latitude = J.num(p["lat"])
                     b.longitude = J.num(p["lon"]); b.mapURL = J.str(p["url"])
                 }
                 b.title = J.str(d["title"]); b.notes = J.str(d["notes"]); b.kindRaw = J.str(d["kind"]); b.targetDate = J.date(d["targetDate"])
                 b.excitement = J.int(d["excitement"]); b.isDone = J.bool(d["isDone"]); b.doneAt = J.date(d["doneAt"]); b.createdAt = J.date(d["createdAt"]) ?? b.createdAt },
             make: { let b = BucketItem(title: ""); $0.insert(b); return b }),
    SyncKind(kind: "readingSession",
             fetch: { (try? $0.fetch(FetchDescriptor<ReadingSession>())) ?? [] }, uuid: { ($0 as! ReadingSession).uuid },
             encode: { m in let r = m as! ReadingSession
                 return ["bookUUID": r.bookUUID, "bookTitle": r.bookTitle, "start": J.date(r.start), "end": J.date(r.end), "pagesRead": r.pagesRead] },
             apply: { d, m in let r = m as! ReadingSession
                 r.bookUUID = J.str(d["bookUUID"]); r.bookTitle = J.str(d["bookTitle"]); r.start = J.date(d["start"]) ?? r.start
                 r.end = J.date(d["end"]); r.pagesRead = J.int(d["pagesRead"]) },
             make: { let r = ReadingSession(); $0.insert(r); return r }),
    SyncKind(kind: "highlight",
             fetch: { (try? $0.fetch(FetchDescriptor<Highlight>())) ?? [] }, uuid: { ($0 as! Highlight).uuid },
             encode: { m in let h = m as! Highlight
                 return ["bookUUID": h.bookUUID, "bookTitle": h.bookTitle, "author": h.author, "text": h.text, "note": h.note,
                         "location": h.location, "createdAt": J.date(h.createdAt), "source": h.source, "externalID": h.externalID] },
             apply: { d, m in let h = m as! Highlight
                 h.bookUUID = J.str(d["bookUUID"]); h.bookTitle = J.str(d["bookTitle"]); h.author = J.str(d["author"]); h.text = J.str(d["text"])
                 h.note = J.str(d["note"]); h.location = J.str(d["location"]); h.createdAt = J.date(d["createdAt"]) ?? h.createdAt
                 h.source = J.str(d["source"]); h.externalID = J.str(d["externalID"]) },
             make: { let h = Highlight(bookTitle: "", author: "", text: ""); $0.insert(h); return h }),
    SyncKind(kind: "subscription",
             fetch: { (try? $0.fetch(FetchDescriptor<Subscription>())) ?? [] }, uuid: { ($0 as! Subscription).uuid },
             encode: { m in let s = m as! Subscription
                 return ["name": s.name, "amount": s.amount, "originalAmount": s.originalAmount, "originalCurrency": s.originalCurrency,
                         "cycle": s.cycleRaw, "nextDate": J.date(s.nextDate), "lastCharged": J.date(s.lastCharged), "category": s.category,
                         "status": s.status, "trialEnds": J.date(s.trialEnds), "previousAmount": s.previousAmount,
                         "priceChangedAt": J.date(s.priceChangedAt), "source": s.source, "notes": s.notes, "createdAt": J.date(s.createdAt)] },
             apply: { d, m in let s = m as! Subscription
                 s.name = J.str(d["name"]); s.amount = J.num(d["amount"]); s.originalAmount = J.num(d["originalAmount"])
                 s.originalCurrency = J.str(d["originalCurrency"]); s.cycleRaw = J.str(d["cycle"]).isEmpty ? "monthly" : J.str(d["cycle"])
                 s.nextDate = J.date(d["nextDate"]); s.lastCharged = J.date(d["lastCharged"]); s.category = J.str(d["category"])
                 s.status = J.str(d["status"]).isEmpty ? "active" : J.str(d["status"]); s.trialEnds = J.date(d["trialEnds"])
                 s.previousAmount = J.num(d["previousAmount"]); s.priceChangedAt = J.date(d["priceChangedAt"])
                 s.source = J.str(d["source"]); s.notes = J.str(d["notes"]); s.createdAt = J.date(d["createdAt"]) ?? s.createdAt },
             make: { let s = Subscription(name: "", amount: 0); $0.insert(s); return s }),
    SyncKind(kind: "document",
             fetch: { (try? $0.fetch(FetchDescriptor<DocItem>())) ?? [] }, uuid: { ($0 as! DocItem).uuid },
             encode: { m in let x = m as! DocItem
                 return ["title": x.title, "kind": x.kindRaw, "number": x.number, "issuer": x.issuer, "issued": J.date(x.issued),
                         "expires": J.date(x.expires), "remindDays": x.remindDays, "notes": x.notes, "source": x.source,
                         "sourceID": x.sourceID, "createdAt": J.date(x.createdAt)] },
             apply: { d, m in let x = m as! DocItem
                 x.title = J.str(d["title"]); x.kindRaw = J.str(d["kind"]); x.number = J.str(d["number"]); x.issuer = J.str(d["issuer"])
                 x.issued = J.date(d["issued"]); x.expires = J.date(d["expires"]); x.remindDays = J.int(d["remindDays"])
                 x.notes = J.str(d["notes"]); x.source = J.str(d["source"]); x.sourceID = J.str(d["sourceID"])
                 x.createdAt = J.date(d["createdAt"]) ?? x.createdAt },
             make: { let x = DocItem(title: ""); $0.insert(x); return x }),
    SyncKind(kind: "focusSession",
             fetch: { (try? $0.fetch(FetchDescriptor<FocusSession>())) ?? [] }, uuid: { ($0 as! FocusSession).uuid },
             encode: { m in let f = m as! FocusSession
                 return ["taskUUID": f.taskUUID, "taskTitle": f.taskTitle, "start": J.date(f.start), "end": J.date(f.end),
                         "plannedMinutes": f.plannedMinutes] },
             apply: { d, m in let f = m as! FocusSession
                 f.taskUUID = J.str(d["taskUUID"]); f.taskTitle = J.str(d["taskTitle"]); f.start = J.date(d["start"]) ?? f.start
                 f.end = J.date(d["end"]); f.plannedMinutes = J.int(d["plannedMinutes"]) },
             make: { let f = FocusSession(); $0.insert(f); return f }),
    SyncKind(kind: "dayPlan",
             fetch: { (try? $0.fetch(FetchDescriptor<DayPlan>())) ?? [] }, uuid: { ($0 as! DayPlan).uuid },
             encode: { m in let p = m as! DayPlan
                 return ["day": p.day, "top": p.top, "taskUUIDs": p.taskUUIDs, "note": p.note, "createdAt": J.date(p.createdAt)] },
             apply: { d, m in let p = m as! DayPlan
                 p.day = J.str(d["day"]); p.top = J.strings(d["top"]); p.taskUUIDs = J.strings(d["taskUUIDs"]); p.note = J.str(d["note"])
                 p.createdAt = J.date(d["createdAt"]) ?? p.createdAt },
             make: { let p = DayPlan(day: ""); $0.insert(p); return p }),
    SyncKind(kind: "trip",
             fetch: { (try? $0.fetch(FetchDescriptor<Trip>())) ?? [] }, uuid: { ($0 as! Trip).uuid },
             encode: { m in let t = m as! Trip
                 return ["title": t.title, "destination": t.destination, "start": J.date(t.start), "end": J.date(t.end),
                         "bucketUUID": t.bucketUUID, "budget": t.budget, "notes": t.notes, "packing": t.packing, "packed": t.packed,
                         "createdAt": J.date(t.createdAt)] },
             apply: { d, m in let t = m as! Trip
                 t.title = J.str(d["title"]); t.destination = J.str(d["destination"]); t.start = J.date(d["start"]); t.end = J.date(d["end"])
                 t.bucketUUID = J.str(d["bucketUUID"]); t.budget = J.num(d["budget"]); t.notes = J.str(d["notes"])
                 t.packing = J.strings(d["packing"]); t.packed = J.strings(d["packed"]); t.createdAt = J.date(d["createdAt"]) ?? t.createdAt },
             make: { let t = Trip(title: ""); $0.insert(t); return t }),
    SyncKind(kind: "booking",
             fetch: { (try? $0.fetch(FetchDescriptor<Booking>())) ?? [] }, uuid: { ($0 as! Booking).uuid },
             encode: { m in let b = m as! Booking
                 return ["tripUUID": b.tripUUID, "kind": b.kindRaw, "title": b.title, "provider": b.provider, "confirmation": b.confirmation,
                         "location": b.location, "start": J.date(b.start), "end": J.date(b.end), "amount": b.amount,
                         "source": b.source, "sourceID": b.sourceID, "createdAt": J.date(b.createdAt)] },
             apply: { d, m in let b = m as! Booking
                 b.tripUUID = J.str(d["tripUUID"]); b.kindRaw = J.str(d["kind"]); b.title = J.str(d["title"]); b.provider = J.str(d["provider"])
                 b.confirmation = J.str(d["confirmation"]); b.location = J.str(d["location"]); b.start = J.date(d["start"]); b.end = J.date(d["end"])
                 b.amount = J.num(d["amount"]); b.source = J.str(d["source"]); b.sourceID = J.str(d["sourceID"])
                 b.createdAt = J.date(d["createdAt"]) ?? b.createdAt },
             make: { let b = Booking(title: ""); $0.insert(b); return b }),
    SyncKind(kind: "bill",
             fetch: { (try? $0.fetch(FetchDescriptor<Bill>())) ?? [] }, uuid: { ($0 as! Bill).uuid },
             encode: { m in let b = m as! Bill
                 return ["name": b.name, "amount": b.amount, "dueDay": b.dueDay, "remindDays": b.remindDays, "match": b.match,
                         "category": b.category, "paidMonths": b.paidMonths, "notes": b.notes, "createdAt": J.date(b.createdAt)] },
             apply: { d, m in let b = m as! Bill
                 b.name = J.str(d["name"]); b.amount = J.num(d["amount"]); b.dueDay = max(1, J.int(d["dueDay"]))
                 b.remindDays = J.int(d["remindDays"]); b.match = J.str(d["match"]); b.category = J.str(d["category"])
                 b.paidMonths = J.strings(d["paidMonths"]); b.notes = J.str(d["notes"]); b.createdAt = J.date(d["createdAt"]) ?? b.createdAt },
             make: { let b = Bill(name: ""); $0.insert(b); return b }),
    SyncKind(kind: "account",
             fetch: { (try? $0.fetch(FetchDescriptor<BankAccount>())) ?? [] }, uuid: { ($0 as! BankAccount).uuid },
             encode: { m in let a = m as! BankAccount
                 return ["name": a.name, "last4": a.last4, "kind": a.kind, "colorIndex": a.colorIndex, "balance": a.balance,
                         "balanceAt": J.date(a.balanceAt), "createdAt": J.date(a.createdAt)] },
             apply: { d, m in let a = m as! BankAccount
                 a.name = J.str(d["name"]); a.last4 = J.str(d["last4"]); a.kind = J.str(d["kind"]).isEmpty ? "card" : J.str(d["kind"])
                 a.colorIndex = J.int(d["colorIndex"]); a.balance = J.num(d["balance"]); a.balanceAt = J.date(d["balanceAt"])
                 a.createdAt = J.date(d["createdAt"]) ?? a.createdAt },
             make: { let a = BankAccount(name: ""); $0.insert(a); return a }),
    SyncKind(kind: "ideaProject",
             fetch: { (try? $0.fetch(FetchDescriptor<IdeaProject>())) ?? [] }, uuid: { ($0 as! IdeaProject).uuid },
             encode: { m in let p = m as! IdeaProject
                 return ["title": p.title, "summary": p.summary, "colorIndex": p.colorIndex, "archived": p.archived,
                         "createdAt": J.date(p.createdAt), "updatedAt": J.date(p.updatedAt)] },
             apply: { d, m in let p = m as! IdeaProject
                 p.title = J.str(d["title"]); p.summary = J.str(d["summary"]); p.colorIndex = J.int(d["colorIndex"])
                 p.archived = d["archived"] as? Bool ?? false
                 p.createdAt = J.date(d["createdAt"]) ?? p.createdAt; p.updatedAt = J.date(d["updatedAt"]) ?? p.updatedAt },
             make: { let p = IdeaProject(title: ""); $0.insert(p); return p }),
    SyncKind(kind: "idea",
             fetch: { (try? $0.fetch(FetchDescriptor<Idea>())) ?? [] }, uuid: { ($0 as! Idea).uuid },
             encode: { m in let i = m as! Idea
                 return ["projectUUID": i.projectUUID, "parentUUID": i.parentUUID, "title": i.title, "body": i.body, "pinned": i.pinned,
                         "createdAt": J.date(i.createdAt), "updatedAt": J.date(i.updatedAt)] },
             apply: { d, m in let i = m as! Idea
                 i.projectUUID = J.str(d["projectUUID"]); i.parentUUID = J.str(d["parentUUID"]); i.title = J.str(d["title"])
                 i.body = J.str(d["body"]); i.pinned = d["pinned"] as? Bool ?? false
                 i.createdAt = J.date(d["createdAt"]) ?? i.createdAt; i.updatedAt = J.date(d["updatedAt"]) ?? i.updatedAt },
             make: { let i = Idea(title: "", projectUUID: ""); $0.insert(i); return i }),
    SyncKind(kind: "goal",
             fetch: { (try? $0.fetch(FetchDescriptor<Goal>())) ?? [] }, uuid: { ($0 as! Goal).uuid },
             encode: { m in let g = m as! Goal
                 return ["title": g.title, "kind": g.kindRaw, "target": g.target, "start": J.date(g.start), "deadline": J.date(g.deadline),
                         "habitUUID": g.habitUUID, "bucketUUID": g.bucketUUID, "steps": g.steps, "stepsDone": g.stepsDone,
                         "doneAt": J.date(g.doneAt), "createdAt": J.date(g.createdAt)] },
             apply: { d, m in let g = m as! Goal
                 g.title = J.str(d["title"]); g.kindRaw = J.str(d["kind"]); g.target = J.num(d["target"]); g.start = J.date(d["start"]) ?? g.start
                 g.deadline = J.date(d["deadline"]); g.habitUUID = J.str(d["habitUUID"]); g.bucketUUID = J.str(d["bucketUUID"])
                 g.steps = J.strings(d["steps"]); g.stepsDone = J.strings(d["stepsDone"]); g.doneAt = J.date(d["doneAt"])
                 g.createdAt = J.date(d["createdAt"]) ?? g.createdAt },
             make: { let g = Goal(title: ""); $0.insert(g); return g }),
]

/// Preferences that follow you between Macs (API keys and sign-ins never leave the Keychain).
/// Preferences that follow you to every device. Connection secrets travel separately, in the key vault.
private let syncedSettings = ["monthlyBudget", "readingGoal", "currencyCode", "assistantName", "userName", "weatherCity", "profileCard", "cardPhoto", "health.daily",
                              "goodreadsUser", "readingAutoSync", "appleCalendarEnabled", "appleRemindersEnabled", "googleCalendarEnabled",
                              "emailExpensesEnabled", "aiMorningBrief", "aiSmartCapture", "assistantSpeaks", "focusMinutes", "launchSound",
                              "notify.tasks", "notify.events", "notify.bills", "notify.habits", "notify.journal", "notify.review",
                              "notify.subscriptions", "notify.documents", "notify.evening", "notify.trips", "notify.morningHour",
                              "notify.habitHour", "notify.journalHour", "notify.eventLead",
                              "merchantRules", "categoryBudgets", "places.home", "places.work", "hiddenTabs", "inbox.windowHours", "inbox.everyHours", "notify.budgets", "notify.bigCharges", "spendAlerts.sent",
                              "assistant.memory", "notify.weeklyMoney", "budget.periodStart", "profile.photo", "voice.natural", "voice.openai"]

// MARK: - Sync engine

/// Two-way sync between Orbit's local database and Supabase. Local first: Orbit works offline and syncs when it can.
/// Changes are found by comparing each item with a fingerprint of what was last synced; when both sides changed,
/// the local edit wins. Deletions are synced as tombstones.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    @Published private(set) var email: String? = CloudAuth.session?.email
    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var status: String?

    /// `waiting`: the keys were stored by an older Orbit with a passphrase; opening Orbit on that Mac converts them.
    enum VaultState: Equatable { case off, waiting, on, error(String) }
    @AppStorage("syncSecrets") var syncSecrets = true
    @Published private(set) var vaultState: VaultState = .off
    private var keyCache: (salt: Data, pass: String, key: SymmetricKey)?
    private var accountKeyCache: (user: String, key: SymmetricKey)?

    private struct State: Codable {
        var cursor = ""                              // last updated_at pulled from the server
        var known: [String: Known] = [:]             // id → what was last synced
        var vaultMac: String?                        // fingerprint of the key vault when last synced
        struct Known: Codable { var kind: String; var hash: String }
    }
    private var state = State()
    /// Lets a test act as two different Macs on one machine.
    var deviceTag = "" { didSet { loadState() } }
    private var stateURL: URL? {
        CloudAuth.session.map { URL.applicationSupportDirectory.appending(path: "Orbit/sync-\($0.userID)\(deviceTag).json") }
    }

    var isSignedIn: Bool { email != nil }

    private init() { loadState() }

    // MARK: Account

    func signIn(email: String, password: String, context: ModelContext) async throws {
        try await CloudAuth.signIn(email: email, password: password)
        self.email = CloudAuth.session?.email
        loadState()
        await sync(context: context)
    }

    func signInWithGoogle(context: ModelContext) async throws {
        try await CloudAuth.signInWithGoogle()
        self.email = CloudAuth.session?.email
        loadState()
        await sync(context: context)
    }

    func signUp(email: String, password: String, context: ModelContext) async throws -> CloudAuth.SignUpResult {
        let result = try await CloudAuth.signUp(email: email, password: password)
        if result == .signedIn {
            self.email = CloudAuth.session?.email
            loadState()
            await sync(context: context)
        }
        return result
    }

    func signOut() {
        CloudAuth.signOut()
        email = nil
        state = State()
        status = nil
        lastSync = nil
        accountKeyCache = nil
        vaultState = .off
    }

    // MARK: Sync

    func syncIfSignedIn(context: ModelContext) async {
        guard isSignedIn, !Snapshot.isActive else { return }
        await sync(context: context)
    }

    func sync(context: ModelContext) async {
        guard !syncing, let session = CloudAuth.session else { return }
        syncing = true
        defer { syncing = false }
        do {
            assignMissingIDs(context: context)
            let pulled = try await pull(context: context)
            let pushed = try await push(context: context, userID: session.userID)
            do { try await syncVault(userID: session.userID) } catch { vaultState = .error(error.localizedDescription) }
            try? context.save()
            saveState()
            SpendingAlerts.check(context: context)
            lastSync = .now
            status = pulled + pushed == 0 ? "Up to date" : "Synced \(pulled) down, \(pushed) up"
        } catch {
            status = error.localizedDescription
        }
    }

    /// Items made before sync existed get their permanent id now.
    private func assignMissingIDs(context: ModelContext) {
        for k in syncKinds {
            for m in k.fetch(context) where k.uuid(m).isEmpty { setUUID(m, UUID().uuidString.lowercased()) }
        }
        try? context.save()
    }

    private func setUUID(_ m: any PersistentModel, _ id: String) {
        switch m {
        case let x as TaskItem: x.uuid = id
        case let x as EventItem: x.uuid = id
        case let x as Habit: x.uuid = id
        case let x as Transaction: x.uuid = id
        case let x as Note: x.uuid = id
        case let x as Book: x.uuid = id
        case let x as BookCategory: x.uuid = id
        case let x as BucketItem: x.uuid = id
        case let x as ReadingSession: x.uuid = id
        case let x as Highlight: x.uuid = id
        case let x as Subscription: x.uuid = id
        case let x as DocItem: x.uuid = id
        case let x as FocusSession: x.uuid = id
        case let x as DayPlan: x.uuid = id
        case let x as Trip: x.uuid = id
        case let x as Booking: x.uuid = id
        case let x as Bill: x.uuid = id
        case let x as BankAccount: x.uuid = id
        case let x as IdeaProject: x.uuid = id
        case let x as Idea: x.uuid = id
        case let x as Goal: x.uuid = id
        default: break
        }
    }

    private func fingerprint(_ d: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Stable uuid for a setting key, so every Mac writes the same row.
    private func settingID(_ key: String) -> String {
        let h = Array(SHA256.hash(data: Data("orbit-setting:\(key)".utf8)))
        var b = Array(h.prefix(16)); b[6] = (b[6] & 0x0F) | 0x50; b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString.lowercased()
    }

    private func settingValue(_ key: String) -> [String: Any] {
        ["key": key, "value": UserDefaults.standard.object(forKey: key) ?? NSNull()]
    }

    private func pull(context: ModelContext) async throws -> Int {
        var index: [String: [String: any PersistentModel]] = [:]
        for k in syncKinds { index[k.kind] = Dictionary(k.fetch(context).map { (k.uuid($0), $0) }, uniquingKeysWith: { a, _ in a }) }
        var applied = 0

        while true {
            var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
            comps.queryItems = [.init(name: "select", value: "id,kind,data,deleted,updated_at"),
                                .init(name: "order", value: "updated_at.asc,id.asc"), .init(name: "limit", value: "1000")]
                + (state.cursor.isEmpty ? [] : [URLQueryItem(name: "updated_at", value: "gt.\(state.cursor)")])
            // Timestamps contain "+00:00": encode the plus so it isn't read as a space.
            comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let rows = try await rest(comps.url!, method: "GET") as? [[String: Any]] ?? []
            for row in rows {
                guard let id = row["id"] as? String, let kindName = row["kind"] as? String else { continue }
                let deleted = J.bool(row["deleted"])
                let data = row["data"] as? [String: Any] ?? [:]
                if let ts = row["updated_at"] as? String { state.cursor = ts }

                if kindName == "vault" || kindName == "vaultkey" { continue } // handled by syncVault
                if kindName == "setting" {
                    guard let key = data["key"] as? String, syncedSettings.contains(key) else { continue }
                    if state.known[id]?.hash == fingerprint(data) { continue } // our own upload coming back
                    let localHash = fingerprint(settingValue(key))
                    if let known = state.known[id], known.hash != localHash { continue } // changed here too: ours wins
                    if deleted || data["value"] is NSNull { UserDefaults.standard.removeObject(forKey: key) }
                    else { UserDefaults.standard.set(data["value"], forKey: key) }
                    state.known[id] = .init(kind: "setting", hash: fingerprint(settingValue(key)))
                    applied += 1
                    continue
                }
                guard let k = syncKinds.first(where: { $0.kind == kindName }) else { continue }
                // Our own upload coming back: nothing to do.
                if !deleted, let known = state.known[id], known.hash == fingerprint(data) { continue }
                let local = index[kindName]?[id]
                if deleted {
                    if let local { context.delete(local); index[kindName]?[id] = nil; applied += 1 }
                    else if state.known[id] == nil { continue } // already gone here
                    state.known[id] = nil
                    continue
                }
                if let local {
                    if let known = state.known[id], known.hash != fingerprint(k.encode(local)) { continue } // edited here too: ours wins
                    k.apply(data, local)
                    state.known[id] = .init(kind: kindName, hash: fingerprint(k.encode(local)))
                } else {
                    if state.known[id] != nil { continue } // deleted here since last sync: the deletion gets pushed
                    let m = k.make(context)
                    setUUID(m, id)
                    k.apply(data, m)
                    index[kindName, default: [:]][id] = m
                    state.known[id] = .init(kind: kindName, hash: fingerprint(k.encode(m)))
                }
                applied += 1
            }
            if rows.count < 1000 { break }
        }
        return applied
    }

    private func push(context: ModelContext, userID: String) async throws -> Int {
        var rows: [[String: Any]] = []
        var newKnown: [String: State.Known] = [:]
        var present = Set<String>()

        for k in syncKinds {
            for m in k.fetch(context) {
                let id = k.uuid(m)
                guard !id.isEmpty else { continue }
                present.insert(id)
                let d = k.encode(m)
                let h = fingerprint(d)
                if state.known[id]?.hash != h {
                    rows.append(["id": id, "user_id": userID, "kind": k.kind, "data": d, "deleted": false])
                    newKnown[id] = .init(kind: k.kind, hash: h)
                }
            }
        }
        for key in syncedSettings {
            let id = settingID(key)
            present.insert(id)
            let d = settingValue(key)
            let h = fingerprint(d)
            if state.known[id]?.hash != h, UserDefaults.standard.object(forKey: key) != nil {
                rows.append(["id": id, "user_id": userID, "kind": "setting", "data": d, "deleted": false])
                newKnown[id] = .init(kind: "setting", hash: h)
            }
        }
        // Synced before but gone here now: tell other devices it was deleted.
        var deletions: [String] = []
        for (id, known) in state.known where !present.contains(id) {
            rows.append(["id": id, "user_id": userID, "kind": known.kind, "data": [String: Any](), "deleted": true])
            deletions.append(id)
        }

        for chunk in stride(from: 0, to: rows.count, by: 200).map({ Array(rows[$0..<min($0 + 200, rows.count)]) }) {
            var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
            comps.queryItems = [.init(name: "on_conflict", value: "user_id,id")]
            _ = try await rest(comps.url!, method: "POST", body: chunk, prefer: "resolution=merge-duplicates,return=minimal")
        }
        for (id, k) in newKnown { state.known[id] = k }
        for id in deletions { state.known[id] = nil }
        return rows.count
    }

    func rest(_ url: URL, method: String, body: Any? = nil, prefer: String? = nil) async throws -> Any? {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await CloudAuth.accessToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
            // A missing table comes back as 404 with the table's name in the message.
            for (table, file) in [("public_cards", "public_cards.sql"), ("shared_lists", "shared_lists.sql")] where (msg ?? "").contains(table) {
                throw CloudError("This needs a one-time setup in Supabase: run supabase/\(file) in your project's SQL Editor.")
            }
            if status == 404 || (msg ?? "").contains("orbit_records") {
                throw CloudError("The Orbit tables aren't set up in Supabase yet (run supabase/schema.sql).")
            }
            if status == 401 { throw CloudError("Your Orbit sign-in expired. Sign in again in Settings › Account.") }
            throw CloudError("Sync error \(status)\(msg.map { ": \($0)" } ?? "")")
        }
        return data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: Public card page

    /// Publishes (or moves) your card to public_cards under `slug`; anyone with the link can read it.
    func publishCard(slug: String, data: [String: Any]) async throws {
        guard let session = CloudAuth.session else { throw CloudError("Sign in under Settings › Account to publish your card.") }
        let base = "\(SupabaseConfig.url)/rest/v1/public_cards"
        _ = try await rest(URL(string: "\(base)?user_id=eq.\(session.userID)")!, method: "DELETE")
        do {
            _ = try await rest(URL(string: base)!, method: "POST", body: [["slug": slug, "user_id": session.userID, "data": data]],
                               prefer: "return=minimal")
        } catch let e as CloudError where e.message.contains("409") || e.message.lowercased().contains("duplicate") {
            throw CloudError("“\(slug)” is taken. Try another name.")
        }
    }

    func unpublishCard() async throws {
        guard let session = CloudAuth.session else { return }
        _ = try await rest(URL(string: "\(SupabaseConfig.url)/rest/v1/public_cards?user_id=eq.\(session.userID)")!, method: "DELETE")
    }

    // MARK: API keys & connections

    // Your Anthropic key, GitHub token and Google sign-ins follow your Orbit account to every device you sign in on,
    // with nothing to type. They're encrypted with a random key that lives in your account (its own row, readable only
    // when signed in as you), so the stored vault is never plain text. Older versions used a sync passphrase instead;
    // a device that still has that passphrase converts the vault the first time it syncs.

    private var vaultID: String { settingID("vault") }
    private var vaultKeyID: String { settingID("vaultkey") }

    func turnOffKeySync() {
        syncSecrets = false
        vaultState = .off
    }

    private func passphraseKey(_ pass: String, salt: Data) -> SymmetricKey {
        if let c = keyCache, c.salt == salt, c.pass == pass { return c.key }
        let k = VaultCrypto.deriveKey(passphrase: pass, salt: salt)
        keyCache = (salt, pass, k)
        return k
    }

    /// The account's vault key; made once by the first device that has something to store.
    private func accountKey(userID: String, create: Bool) async throws -> SymmetricKey? {
        if let c = accountKeyCache, c.user == userID { return c.key }
        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
        comps.queryItems = [.init(name: "id", value: "eq.\(vaultKeyID)"), .init(name: "select", value: "data,deleted")]
        let rows = try await rest(comps.url!, method: "GET") as? [[String: Any]] ?? []
        if let row = rows.first, !J.bool(row["deleted"]), let text = (row["data"] as? [String: Any])?["key"] as? String,
           let raw = Data(base64Encoded: text), raw.count == 32 {
            let k = SymmetricKey(data: raw)
            accountKeyCache = (userID, k)
            return k
        }
        guard create else { return nil }
        let k = SymmetricKey(size: .bits256)
        let raw = k.withUnsafeBytes { Data($0) }
        var up = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
        up.queryItems = [.init(name: "on_conflict", value: "user_id,id")]
        _ = try await rest(up.url!, method: "POST", body: [["id": vaultKeyID, "user_id": userID, "kind": "vaultkey",
                                                             "data": ["key": raw.base64EncodedString()], "deleted": false]],
                           prefer: "resolution=merge-duplicates,return=minimal")
        accountKeyCache = (userID, k)
        return k
    }

    private func vaultPayload() -> [String: Any] {
        var config: [String: Any] = [:]
        for k in ["googleClientID", "githubUser"] { if let v = UserDefaults.standard.string(forKey: k), !v.isEmpty { config[k] = v } }
        if let a = UserDefaults.standard.stringArray(forKey: "gmailAccounts"), !a.isEmpty { config["gmailAccounts"] = a }
        return ["secrets": Keychain.syncable(), "config": config]
    }

    private func isEmpty(_ p: [String: Any]) -> Bool {
        (p["secrets"] as? [String: String] ?? [:]).isEmpty && (p["config"] as? [String: Any] ?? [:]).isEmpty
    }

    private func applyPayload(_ p: [String: Any]) {
        Keychain.merge(p["secrets"] as? [String: String] ?? [:])
        let config = p["config"] as? [String: Any] ?? [:]
        for k in ["googleClientID", "githubUser"] { if let v = config[k] as? String, !v.isEmpty { UserDefaults.standard.set(v, forKey: k) } }
        if let a = config["gmailAccounts"] as? [String] { UserDefaults.standard.set(a, forKey: "gmailAccounts") }
        InboxStore.shared.reloadAccounts()
        GitHubStore.shared.reloadToken()
        AIAssistant.shared.reloadKey()
    }

    /// Union of both sides; where both have a value, `preferLocal` decides.
    private func mergePayloads(remote: [String: Any], local: [String: Any], preferLocal: Bool) -> [String: Any] {
        var secrets = remote["secrets"] as? [String: String] ?? [:]
        for (k, v) in local["secrets"] as? [String: String] ?? [:] where preferLocal || secrets[k] == nil { secrets[k] = v }
        var config = remote["config"] as? [String: Any] ?? [:]
        let localConfig = local["config"] as? [String: Any] ?? [:]
        for (k, v) in localConfig where k != "gmailAccounts" && (preferLocal || config[k] == nil) { config[k] = v }
        let accounts = Set((config["gmailAccounts"] as? [String] ?? []) + (localConfig["gmailAccounts"] as? [String] ?? []))
        if !accounts.isEmpty { config["gmailAccounts"] = accounts.sorted() }
        return ["secrets": secrets, "config": config]
    }

    private func plain(_ p: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys])) ?? Data() }

    private func syncVault(userID: String) async throws {
        guard syncSecrets else { vaultState = .off; return }
        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
        comps.queryItems = [.init(name: "id", value: "eq.\(vaultID)"), .init(name: "select", value: "data,deleted")]
        let rows = try await rest(comps.url!, method: "GET") as? [[String: Any]] ?? []
        let remote = rows.first.flatMap { J.bool($0["deleted"]) ? nil : $0["data"] as? [String: Any] }
        let local = vaultPayload()

        var remotePayload: [String: Any]?
        var remotePlain: Data?
        var converting = false
        if let remote, let box = remote["box"] as? String {
            if (remote["v"] as? Int ?? 1) >= 2 {
                guard let k = try await accountKey(userID: userID, create: false), let opened = VaultCrypto.open(box, key: k) else {
                    throw CloudError("Couldn't read your synced keys. Sign out and in again, or add them in Settings.")
                }
                remotePlain = opened
            } else {
                // The old passphrase vault: only a device that still has the passphrase can open (and convert) it.
                if let pass = Keychain.read("sync-passphrase"), !pass.isEmpty,
                   let salt = (remote["salt"] as? String).flatMap({ Data(base64Encoded: $0) }),
                   let opened = VaultCrypto.open(box, key: passphraseKey(pass, salt: salt)) {
                    remotePlain = opened
                    converting = true
                } else if isEmpty(local) {
                    vaultState = .waiting // a device that has the keys will replace the old vault
                    return
                }
                // Otherwise this device has the keys itself but not the old passphrase: it starts a fresh vault below.
            }
            remotePayload = remotePlain.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }

        guard let remotePayload else {
            // Nothing stored yet: this device starts the vault if it has anything to share.
            if !isEmpty(local), let k = try await accountKey(userID: userID, create: true) {
                let data = plain(local)
                try await uploadVault(data, key: k, userID: userID)
                state.vaultMac = VaultCrypto.mac(data, key: k)
            }
            vaultState = .on
            return
        }

        guard let k = try await accountKey(userID: userID, create: true) else { return }
        let localMac = VaultCrypto.mac(plain(local), key: k)
        if !converting, localMac == remote?["mac"] as? String { state.vaultMac = localMac; vaultState = .on; return }
        let localChanged = converting || (state.vaultMac != nil && state.vaultMac != localMac)
        let merged = mergePayloads(remote: remotePayload, local: local, preferLocal: localChanged)
        applyPayload(merged)
        let mergedPlain = plain(merged)
        if converting || mergedPlain != remotePlain { try await uploadVault(mergedPlain, key: k, userID: userID) }
        if converting { Keychain.delete("sync-passphrase") }
        state.vaultMac = VaultCrypto.mac(mergedPlain, key: k)
        vaultState = .on
    }

    /// Test hook: stores a vault the way Orbit did before 1.14 (encrypted with a sync passphrase).
    func storeLegacyVaultForTest(_ payload: [String: Any], passphrase: String) async throws {
        guard let session = CloudAuth.session else { return }
        let salt = VaultCrypto.newSalt()
        let k = VaultCrypto.deriveKey(passphrase: passphrase, salt: salt)
        let p = plain(payload)
        let data: [String: Any] = ["v": 1, "salt": salt.base64EncodedString(), "box": try VaultCrypto.seal(p, key: k), "mac": VaultCrypto.mac(p, key: k)]
        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
        comps.queryItems = [.init(name: "on_conflict", value: "user_id,id")]
        _ = try await rest(comps.url!, method: "POST", body: [["id": vaultID, "user_id": session.userID, "kind": "vault", "data": data, "deleted": false]],
                           prefer: "resolution=merge-duplicates,return=minimal")
    }

    private func uploadVault(_ plaintext: Data, key: SymmetricKey, userID: String) async throws {
        let data: [String: Any] = ["v": 2, "box": try VaultCrypto.seal(plaintext, key: key), "mac": VaultCrypto.mac(plaintext, key: key)]
        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
        comps.queryItems = [.init(name: "on_conflict", value: "user_id,id")]
        _ = try await rest(comps.url!, method: "POST", body: [["id": vaultID, "user_id": userID, "kind": "vault", "data": data, "deleted": false]],
                           prefer: "resolution=merge-duplicates,return=minimal")
    }

    // MARK: State

    private func loadState() {
        guard let url = stateURL, let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(State.self, from: data) else {
            state = State(); return
        }
        state = s
    }

    private func saveState() {
        guard let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
