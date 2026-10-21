import Foundation
import SwiftUI

/// Reads a GitHub profile, repositories, pull requests, issues and activity.
/// Works with just a username (public data); a token adds private repos and the contribution calendar.
@MainActor
final class GitHubStore: ObservableObject {
    static let shared = GitHubStore()

    struct Profile { let login: String; let name: String; let bio: String; let avatarURL: String
                     let followers: Int; let following: Int; let publicRepos: Int; let htmlURL: String }

    struct Repo: Identifiable {
        let id: Int
        let name: String
        let fullName: String
        let description: String
        let language: String
        let stars: Int
        let forks: Int
        let openIssues: Int
        let isPrivate: Bool
        let isFork: Bool
        let isArchived: Bool
        let pushedAt: Date?
        let htmlURL: String
    }

    struct IssueItem: Identifiable {
        let id: Int
        let title: String
        let repo: String
        let number: Int
        let updatedAt: Date?
        let htmlURL: String
        let isDraft: Bool
    }

    struct Activity: Identifiable {
        let id: String
        let summary: String
        let repo: String
        let at: Date?
        let symbol: String
    }

    struct ContributionDay: Hashable { let date: Date; let count: Int }

    @Published private(set) var profile: Profile?
    @Published private(set) var repos: [Repo] = []
    @Published private(set) var pullRequests: [IssueItem] = []
    @Published private(set) var issues: [IssueItem] = []
    @Published private(set) var activity: [Activity] = []
    @Published private(set) var contributions: [ContributionDay] = []
    @Published private(set) var totalContributions = 0
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var hasToken = Keychain.read("github-token") != nil

    @AppStorage("githubUser") var username = ""

    var isConnected: Bool { !username.isEmpty || hasToken }

    func saveToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { Keychain.delete("github-token") } else { Keychain.write(t, account: "github-token") }
        hasToken = Keychain.read("github-token") != nil
    }

    func disconnect() {
        Keychain.delete("github-token")
        hasToken = false
        username = ""
        profile = nil; repos = []; pullRequests = []; issues = []; activity = []; contributions = []
        lastRefresh = nil
    }

    // MARK: Loading

    func refresh() async {
        guard isConnected, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let me = try await object(hasToken ? "/user" : "/users/\(username)")
            let login = me["login"] as? String ?? username
            username = login
            profile = Profile(login: login, name: me["name"] as? String ?? "", bio: me["bio"] as? String ?? "",
                              avatarURL: me["avatar_url"] as? String ?? "",
                              followers: me["followers"] as? Int ?? 0, following: me["following"] as? Int ?? 0,
                              publicRepos: (me["public_repos"] as? Int ?? 0) + (me["total_private_repos"] as? Int ?? 0),
                              htmlURL: me["html_url"] as? String ?? "https://github.com/\(login)")

            async let repoJSON = array(hasToken ? "/user/repos?sort=pushed&per_page=100&affiliation=owner,collaborator,organization_member"
                                                : "/users/\(login)/repos?sort=pushed&per_page=100")
            async let prJSON = object("/search/issues?q=\(q("is:open is:pr author:\(login) archived:false"))&sort=updated&per_page=20")
            async let issueJSON = object("/search/issues?q=\(q("is:open is:issue assignee:\(login) archived:false"))&sort=updated&per_page=20")
            async let eventJSON = array("/users/\(login)/events?per_page=40")

            repos = try await repoJSON.map(Self.repo)
            pullRequests = ((try await prJSON)["items"] as? [[String: Any]] ?? []).map(Self.issue)
            issues = ((try await issueJSON)["items"] as? [[String: Any]] ?? []).map(Self.issue)
            activity = (try await eventJSON).compactMap(Self.activity)
            if hasToken { try? await loadContributions(login: login) } else { contributions = []; totalContributions = 0 }
            lastRefresh = .now
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadContributions(login: String) async throws {
        let query = """
        query($login: String!) { user(login: $login) { contributionsCollection { contributionCalendar {
          totalContributions weeks { contributionDays { date contributionCount } } } } } }
        """
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["login": login]])
        var req = request("https://api.github.com/graphql")
        req.httpMethod = "POST"
        req.httpBody = body
        let json = try await fetch(req) as? [String: Any]
        let cal = (((json?["data"] as? [String: Any])?["user"] as? [String: Any])?["contributionsCollection"] as? [String: Any])?["contributionCalendar"] as? [String: Any]
        totalContributions = cal?["totalContributions"] as? Int ?? 0
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        contributions = (cal?["weeks"] as? [[String: Any]] ?? []).flatMap { w in
            (w["contributionDays"] as? [[String: Any]] ?? []).compactMap { d in
                guard let s = d["date"] as? String, let date = df.date(from: s) else { return nil }
                return ContributionDay(date: date, count: d["contributionCount"] as? Int ?? 0)
            }
        }
    }

    // MARK: HTTP

    private func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&:"))) ?? s }

    private func request(_ url: String) -> URLRequest {
        var req = URLRequest(url: URL(string: url)!)
        req.timeoutInterval = 30
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = Keychain.read("github-token") { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func fetch(_ req: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return try JSONSerialization.jsonObject(with: data)
        case 401: throw GitHubError("GitHub rejected the token. Check it in Settings › Connections.")
        case 403, 429: throw GitHubError("GitHub rate limit reached. Adding a token raises the limit.")
        case 404: throw GitHubError("GitHub user not found.")
        default: throw GitHubError("GitHub returned an error (\(status)).")
        }
    }

    private func object(_ path: String) async throws -> [String: Any] {
        try await fetch(request("https://api.github.com" + path)) as? [String: Any] ?? [:]
    }

    private func array(_ path: String) async throws -> [[String: Any]] {
        try await fetch(request("https://api.github.com" + path)) as? [[String: Any]] ?? []
    }

    // MARK: Mapping

    private static let iso = ISO8601DateFormatter()

    private static func repo(_ j: [String: Any]) -> Repo {
        Repo(id: j["id"] as? Int ?? 0, name: j["name"] as? String ?? "", fullName: j["full_name"] as? String ?? "",
             description: j["description"] as? String ?? "", language: j["language"] as? String ?? "",
             stars: j["stargazers_count"] as? Int ?? 0, forks: j["forks_count"] as? Int ?? 0,
             openIssues: j["open_issues_count"] as? Int ?? 0, isPrivate: j["private"] as? Bool ?? false,
             isFork: j["fork"] as? Bool ?? false, isArchived: j["archived"] as? Bool ?? false,
             pushedAt: (j["pushed_at"] as? String).flatMap(iso.date), htmlURL: j["html_url"] as? String ?? "")
    }

    private static func issue(_ j: [String: Any]) -> IssueItem {
        let repoURL = j["repository_url"] as? String ?? ""
        return IssueItem(id: j["id"] as? Int ?? 0, title: j["title"] as? String ?? "",
                         repo: repoURL.split(separator: "/").suffix(2).joined(separator: "/"),
                         number: j["number"] as? Int ?? 0, updatedAt: (j["updated_at"] as? String).flatMap(iso.date),
                         htmlURL: j["html_url"] as? String ?? "", isDraft: j["draft"] as? Bool ?? false)
    }

    private static func activity(_ j: [String: Any]) -> Activity? {
        let type = j["type"] as? String ?? ""
        let repo = (j["repo"] as? [String: Any])?["name"] as? String ?? ""
        let payload = j["payload"] as? [String: Any] ?? [:]
        let action = payload["action"] as? String ?? ""
        let summary: String, symbol: String
        switch type {
        case "PushEvent":
            let n = payload["size"] as? Int ?? (payload["commits"] as? [Any])?.count ?? 1
            let branch = (payload["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
            summary = "Pushed \(n) commit\(n == 1 ? "" : "s")\(branch.isEmpty ? "" : " to \(branch)")"; symbol = "arrow.up.circle.fill"
        case "PullRequestEvent":
            let title = (payload["pull_request"] as? [String: Any])?["title"] as? String ?? ""
            summary = "\(action.capitalized) PR: \(title)"; symbol = "arrow.triangle.pull"
        case "IssuesEvent":
            let title = (payload["issue"] as? [String: Any])?["title"] as? String ?? ""
            summary = "\(action.capitalized) issue: \(title)"; symbol = "exclamationmark.circle"
        case "IssueCommentEvent", "PullRequestReviewCommentEvent", "CommitCommentEvent":
            summary = "Commented"; symbol = "text.bubble"
        case "PullRequestReviewEvent": summary = "Reviewed a pull request"; symbol = "checkmark.bubble"
        case "CreateEvent":
            summary = "Created \(payload["ref_type"] as? String ?? "")\((payload["ref"] as? String).map { " \($0)" } ?? "")"; symbol = "plus.circle"
        case "DeleteEvent": summary = "Deleted \(payload["ref_type"] as? String ?? "") \(payload["ref"] as? String ?? "")"; symbol = "minus.circle"
        case "WatchEvent": summary = "Starred"; symbol = "star"
        case "ForkEvent": summary = "Forked"; symbol = "tuningfork"
        case "ReleaseEvent": summary = "Published a release"; symbol = "shippingbox"
        case "PublicEvent": summary = "Made public"; symbol = "globe"
        default: return nil
        }
        return Activity(id: j["id"] as? String ?? UUID().uuidString, summary: summary, repo: repo,
                        at: (j["created_at"] as? String).flatMap(iso.date), symbol: symbol)
    }
}

struct GitHubError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum LanguageColor {
    static func color(_ lang: String) -> Color {
        switch lang {
        case "Swift": Color(hex: 0xF05138)
        case "TypeScript": Color(hex: 0x3178C6)
        case "JavaScript": Color(hex: 0xF1E05A)
        case "Python": Color(hex: 0x3572A5)
        case "Go": Color(hex: 0x00ADD8)
        case "Rust": Color(hex: 0xDEA584)
        case "Java": Color(hex: 0xB07219)
        case "Kotlin": Color(hex: 0xA97BFF)
        case "C#": Color(hex: 0x178600)
        case "C++": Color(hex: 0xF34B7D)
        case "C": Color(hex: 0x555555)
        case "Ruby": Color(hex: 0x701516)
        case "PHP": Color(hex: 0x4F5D95)
        case "HTML": Color(hex: 0xE34C26)
        case "CSS": Color(hex: 0x563D7C)
        case "Shell": Color(hex: 0x89E051)
        case "Dart": Color(hex: 0x00B4AB)
        case "Jupyter Notebook": Color(hex: 0xDA5B0B)
        default: Theme.inkMuted
        }
    }
}
