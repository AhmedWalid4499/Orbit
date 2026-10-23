import SwiftUI

struct GitHubView: View {
    @ObservedObject private var gh = GitHubStore.shared
    @Environment(\.openURL) private var openURL

    @State private var filter = "Active"
    @State private var query = ""

    private var visibleRepos: [GitHubStore.Repo] {
        var list = gh.repos
        switch filter {
        case "Active": list = list.filter { !$0.isArchived && !$0.isFork }
        case "Private": list = list.filter(\.isPrivate)
        case "Public": list = list.filter { !$0.isPrivate }
        case "Forks": list = list.filter(\.isFork)
        case "Archived": list = list.filter(\.isArchived)
        default: break
        }
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
        }
        return list
    }

    var body: some View {
        Group {
            if gh.isConnected {
                dashboard
            } else {
                GitHubConnectCard().frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: gh.username + "\(gh.hasToken)") {
            if gh.isConnected, gh.lastRefresh == nil || Date.now.timeIntervalSince(gh.lastRefresh!) > 600 { await gh.refresh() }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = gh.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(13))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.peach.opacity(0.5)))
                }
                statRow
                if !gh.contributions.isEmpty { contributionCard }
                AdaptiveStack(spacing: 22) {
                    reposCard
                    VStack(spacing: 22) {
                        listCard("Your open pull requests", items: gh.pullRequests, symbol: "arrow.triangle.pull",
                                 empty: "No open pull requests.")
                        listCard("Issues assigned to you", items: gh.issues, symbol: "exclamationmark.circle",
                                 empty: "Nothing assigned.")
                        activityCard
                    }
                    .frame(width: Platform.isPhone ? nil : 380)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: gh.profile?.avatarURL ?? "")) { $0.resizable() } placeholder: { Circle().fill(Theme.card) }
                .frame(width: 60, height: 60).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(gh.profile?.name.isEmpty == false ? gh.profile!.name : "@\(gh.username)").font(Theme.display(34))
                HStack(spacing: 10) {
                    Text("@\(gh.username)")
                    if let p = gh.profile {
                        Text("· \(p.followers) followers · \(p.following) following")
                    }
                    if !gh.hasToken { Text("· public data only").foregroundStyle(Theme.inkMuted) }
                }
                .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                if let bio = gh.profile?.bio, !bio.isEmpty { Text(bio).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary) }
            }
            Spacer()
            if gh.loading { ProgressView().controlSize(.small) }
            else if let last = gh.lastRefresh {
                Text("Updated \(last.formatted(.relative(presentation: .named)))").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Button { Task { await gh.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(SoftButtonStyle()).disabled(gh.loading)
            if let url = gh.profile.flatMap({ URL(string: $0.htmlURL) }) {
                Button { openURL(url) } label: { Label("Open GitHub", systemImage: "arrow.up.right") }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            GHStat(value: "\(gh.repos.filter { !$0.isArchived }.count)", label: "Repositories", color: Theme.lime)
            GHStat(value: "\(gh.repos.filter { !$0.isFork }.reduce(0) { $0 + $1.stars })", label: "Stars earned", color: Theme.orange)
            GHStat(value: "\(gh.pullRequests.count)", label: "Open PRs", color: Theme.cyan)
            GHStat(value: "\(gh.issues.count)", label: "Assigned issues", color: Theme.pink)
            GHStat(value: gh.hasToken ? "\(gh.totalContributions)" : "—", label: "Contributions (year)", color: Theme.purple)
        }
    }

    /// Last year of contributions: single hue, light → dark.
    private var contributionCard: some View {
        let maxCount = max(gh.contributions.map(\.count).max() ?? 1, 1)
        let weeks = stride(from: 0, to: gh.contributions.count, by: 7).map { Array(gh.contributions[$0..<min($0 + 7, gh.contributions.count)]) }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Contributions").font(Theme.display(22))
                    Spacer()
                    Text("\(gh.totalContributions) in the last year").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                }
                HStack(alignment: .top, spacing: 3) {
                    ForEach(weeks.indices, id: \.self) { w in
                        VStack(spacing: 3) {
                            ForEach(weeks[w], id: \.self) { d in
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(d.count == 0 ? Theme.line : Theme.ink.opacity(0.25 + 0.75 * Double(d.count) / Double(maxCount)))
                                    .frame(width: 11, height: 11)
                                    .help("\(d.count) contribution\(d.count == 1 ? "" : "s") on \(d.date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var reposCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Projects").font(Theme.display(22))
                    Text("\(visibleRepos.count)").font(Theme.display(22, weight: .regular)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                        TextField("Filter", text: $query).textFieldStyle(.plain).frame(width: 110)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.canvas))
                }
                HStack(spacing: 6) {
                    ForEach(["Active", "All", "Public", "Private", "Forks", "Archived"], id: \.self) { f in
                        Button(f) { filter = f }
                            .buttonStyle(.plain)
                            .font(Theme.ui(12, weight: .medium))
                            .foregroundStyle(filter == f ? Theme.onInverse : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(filter == f ? Theme.inverse : Theme.canvas))
                    }
                }
                if visibleRepos.isEmpty && !gh.loading { EmptyHint(symbol: "folder", text: "No repositories here.") }
                ForEach(visibleRepos) { r in
                    Button { if let u = URL(string: r.htmlURL) { openURL(u) } } label: { RepoRow(repo: r) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func listCard(_ title: String, items: [GitHubStore.IssueItem], symbol: String, empty: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(Theme.display(20))
                if items.isEmpty { EmptyHint(symbol: "checkmark.seal", text: empty) }
                ForEach(items.prefix(8)) { i in
                    Button { if let u = URL(string: i.htmlURL) { openURL(u) } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol).foregroundStyle(i.isDraft ? Theme.inkMuted : Theme.good).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.title).font(Theme.ui(13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(i.repo) #\(i.number)\(i.updatedAt.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? "")")
                                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent activity").font(Theme.display(20))
                if gh.activity.isEmpty { EmptyHint(symbol: "clock", text: "No recent public activity.") }
                ForEach(gh.activity.prefix(12)) { a in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: a.symbol).font(.system(size: 12)).foregroundStyle(Theme.inkSecondary).frame(width: 18).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.summary).font(Theme.ui(13)).lineLimit(2)
                            Text("\(a.repo)\(a.at.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? "")")
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
        }
    }
}

struct GHStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(Theme.display(28)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.ui(12, weight: .semibold)).opacity(0.8)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
    }
}

struct RepoRow: View {
    let repo: GitHubStore.Repo
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(repo.name).font(Theme.ui(15, weight: .semibold))
                if repo.isPrivate { Label("Private", systemImage: "lock.fill").labelStyle(.titleAndIcon).font(Theme.ui(10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().strokeBorder(Theme.line)) }
                if repo.isFork { Text("Fork").font(Theme.ui(10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().strokeBorder(Theme.line)) }
                if repo.isArchived { Text("Archived").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.orange) }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted).opacity(hovering ? 1 : 0)
            }
            if !repo.description.isEmpty {
                Text(repo.description).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
            }
            HStack(spacing: 14) {
                if !repo.language.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(LanguageColor.color(repo.language)).frame(width: 9, height: 9)
                        Text(repo.language)
                    }
                }
                if repo.stars > 0 { Label("\(repo.stars)", systemImage: "star") }
                if repo.forks > 0 { Label("\(repo.forks)", systemImage: "tuningfork") }
                if repo.openIssues > 0 { Label("\(repo.openIssues) open", systemImage: "exclamationmark.circle") }
                Spacer()
                if let p = repo.pushedAt { Text("Updated \(p.formatted(.relative(presentation: .named)))") }
            }
            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(hovering ? Theme.cardHover : Theme.canvas))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Shown on the GitHub tab and in Settings › Connections.
struct GitHubConnectCard: View {
    @ObservedObject private var gh = GitHubStore.shared
    @State private var user = ""
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.onInverse)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.inverse))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect GitHub").font(Theme.display(24))
                    Text("See your projects, pull requests, issues and activity.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
            }
            TextField("GitHub username", text: $user).textFieldStyle(.roundedBorder)
            SecureField("Personal access token (optional)", text: $token).textFieldStyle(.roundedBorder)
            Text("With just a username Orbit shows public data. A token adds private repos and your contribution graph. Create a fine-grained token with read-only access at github.com › Settings › Developer settings. It's stored in your Keychain.")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            HStack {
                Link("Create a token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    .font(Theme.ui(12))
                Spacer()
                Button("Connect") {
                    gh.saveToken(token)
                    gh.username = user.trimmingCharacters(in: .whitespaces)
                    token = ""
                    Task { await gh.refresh() }
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 130)
                .disabled(user.trimmingCharacters(in: .whitespaces).isEmpty && token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }
}
