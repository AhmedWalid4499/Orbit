import SwiftUI
import SwiftData

/// Ideas: your writing projects and the ideas in them. Jot an idea down (or ask the assistant to), open it to keep
/// writing, and let it grow into smaller ideas, by hand or with "Grow with AI".
struct IdeasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IdeaProject.updatedAt, order: .reverse) private var projects: [IdeaProject]
    @Query(sort: \Idea.updatedAt, order: .reverse) private var ideas: [Idea]
    @AppStorage("ideas.selected") private var selectedID = ""
    @State private var newIdea = ""
    @State private var creating = false
    @State private var open: Idea?
    @State private var editingProject: IdeaProject?

    static let tints: [Color] = [Theme.lime, Theme.cyan, Theme.pink, Theme.peach, Theme.lavender, Theme.mint, Theme.sand]

    private var live: [IdeaProject] { projects.filter { !$0.archived } }
    private var selected: IdeaProject? { live.first { $0.uuid == selectedID } ?? live.first }

    var body: some View {
        Group {
            if Platform.isPhone {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        projectChips
                        if let p = selected { projectPage(p) } else { empty }
                    }
                    .padding(.horizontal, Theme.pagePadding).padding(.top, 8).padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    sidebar
                    Rectangle().fill(Theme.line).frame(width: 1)
                    ScrollView {
                        Group { if let p = selected { projectPage(p) } else { empty } }
                            .padding(28).frame(maxWidth: 980, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(item: $open) { IdeaSheet(idea: $0) }
        .sheet(isPresented: $creating) { ProjectEditor(project: nil) { selectedID = $0.uuid } }
        .sheet(item: $editingProject) { ProjectEditor(project: $0) { _ in } }
    }

    // MARK: Projects

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ideas").font(Theme.display(30))
                Spacer()
                Button { creating = true } label: { Image(systemName: "plus") }.buttonStyle(SoftButtonStyle()).help("New project")
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(live) { p in
                        let count = ideas.filter { $0.projectUUID == p.uuid }.count
                        Button { selectedID = p.uuid } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6).fill(Self.tints[p.colorIndex % Self.tints.count]).frame(width: 12, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                                    Text("\(count) idea\(count == 1 ? "" : "s")").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(selected?.uuid == p.uuid ? Theme.card : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { projectMenu(p) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(20)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var projectChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(live) { p in
                    let on = selected?.uuid == p.uuid
                    Button { selectedID = p.uuid } label: {
                        Text(p.title).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(on ? Theme.stickerInk : Theme.ink)
                            .background(Capsule().fill(on ? Self.tints[p.colorIndex % Self.tints.count] : Theme.card))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { projectMenu(p) }
                }
                Button { creating = true } label: { Label("Project", systemImage: "plus").font(Theme.ui(13, weight: .semibold)) }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private func projectMenu(_ p: IdeaProject) -> some View {
        Button("Rename / describe") { editingProject = p }
        Button(p.archived ? "Unarchive" : "Archive") { p.archived.toggle(); try? context.save() }
        Button("Delete project and its ideas", role: .destructive) {
            ideas.filter { $0.projectUUID == p.uuid }.forEach(context.delete)
            context.delete(p)
            try? context.save()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "lightbulb.max.fill").font(.system(size: 30)).foregroundStyle(Theme.stickerInk)
                .frame(width: 64, height: 64).background(Circle().fill(Theme.lime))
            Text("Where your ideas grow").font(Theme.display(26))
            Text("Make a project for each thing you're writing. Drop ideas in whenever they come, or just tell \(AssistantName.current): “add an idea to my novel: the sister knew all along”. Open an idea to keep writing on it and grow it into more.")
                .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            Button { creating = true } label: { Label("New project", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle()).fixedSize()
        }
        .padding(24)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
    }

    // MARK: A project's ideas

    private func projectPage(_ p: IdeaProject) -> some View {
        let mine = ideas.filter { $0.projectUUID == p.uuid }
        let top = mine.filter { $0.parentUUID.isEmpty }.sorted { ($0.pinned ? 1 : 0, $0.updatedAt) > ($1.pinned ? 1 : 0, $1.updatedAt) }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.title).font(Theme.display(Platform.isPhone ? 26 : 34))
                    Button { editingProject = p } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                }
                if !p.summary.isEmpty { Text(p.summary).font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary) }
                Text("\(top.count) idea\(top.count == 1 ? "" : "s") · \(mine.count - top.count) grown from them").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(Theme.inkMuted)
                TextField("A new idea for \(p.title)…", text: $newIdea, axis: .vertical)
                    .textFieldStyle(.plain).font(Theme.ui(15)).lineLimit(1...4)
                    .onSubmit { add(to: p) }
                Button("Add") { add(to: p) }.buttonStyle(PrimaryButtonStyle()).fixedSize()
                    .disabled(newIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            if top.isEmpty {
                Text("No ideas yet. The first one is the hardest; write anything.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Platform.isPhone ? 300 : 260), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(top) { idea in
                    IdeaCard(idea: idea, branches: mine.filter { $0.parentUUID == idea.uuid }.count,
                             tint: Self.tints[p.colorIndex % Self.tints.count]) { open = idea }
                }
            }
        }
    }

    private func add(to p: IdeaProject) {
        let text = newIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        IdeaStore.add(text, to: p, context: context)
        newIdea = ""
    }
}

/// An idea on the project page: its title, the start of what you wrote, and how much it has grown.
private struct IdeaCard: View {
    let idea: Idea
    let branches: Int
    let tint: Color
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(idea.title).font(Theme.ui(16, weight: .semibold)).multilineTextAlignment(.leading).lineLimit(3)
                    Spacer(minLength: 6)
                    if idea.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Theme.inkMuted) }
                }
                if !idea.body.isEmpty {
                    Text(idea.body).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).lineLimit(4).multilineTextAlignment(.leading)
                }
                HStack(spacing: 10) {
                    if branches > 0 { Label("\(branches)", systemImage: "arrow.triangle.branch").font(Theme.ui(11, weight: .semibold)) }
                    Text(idea.updatedAt.formatted(.relative(presentation: .named))).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 14) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One idea, open: write on it, see what grew from it, add branches yourself or let the AI suggest some.
struct IdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var idea: Idea
    @Query(sort: \Idea.createdAt) private var all: [Idea]
    @Query private var projects: [IdeaProject]
    @ObservedObject private var ai = AIAssistant.shared
    @State private var branch = ""
    @State private var growing = false
    @State private var error: String?
    @State private var child: Idea?

    private var branches: [Idea] { all.filter { $0.parentUUID == idea.uuid } }
    private var project: IdeaProject? { projects.first { $0.uuid == idea.projectUUID } }
    private var parent: Idea? { all.first { $0.uuid == idea.parentUUID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(project?.title ?? "Idea").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    if let parent { Text("Grew from “\(parent.title)”").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                }
                Spacer()
                Button { idea.pinned.toggle(); touch() } label: { Image(systemName: idea.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).help(idea.pinned ? "Unpin" : "Pin to the top")
                Menu {
                    Button("Delete idea", role: .destructive) {
                        for b in branches { b.parentUUID = idea.parentUUID }   // its branches move up instead of vanishing
                        context.delete(idea)
                        try? context.save()
                        dismiss()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
                Button("Done") { touch(); dismiss() }.buttonStyle(PrimaryButtonStyle()).fixedSize().keyboardShortcut(.defaultAction)
            }
            .padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Idea", text: $idea.title, axis: .vertical)
                        .textFieldStyle(.plain).font(Theme.display(26)).onChange(of: idea.title) { touch() }
                    ZStack(alignment: .topLeading) {
                        if idea.body.isEmpty {
                            Text("Keep writing… what happens, who's in it, why it matters, a line of dialogue.")
                                .font(Theme.ui(15)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $idea.body)
                            .font(Theme.ui(15)).lineSpacing(4).scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .onChange(of: idea.body) { touch() }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Grown from this", systemImage: "arrow.triangle.branch").font(Theme.ui(14, weight: .semibold))
                            Spacer()
                            if ai.hasKey {
                                Button { Task { await grow() } } label: {
                                    HStack(spacing: 6) {
                                        AssistantAvatar(size: 18, busy: growing)
                                        Text(growing ? "Growing…" : "Grow with AI")
                                    }
                                }
                                .buttonStyle(SoftButtonStyle()).disabled(growing)
                            }
                        }
                        if let error { Text(error).font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                        ForEach(branches) { b in
                            Button { child = b } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(b.title).font(Theme.ui(14, weight: .semibold)).multilineTextAlignment(.leading)
                                        if !b.body.isEmpty { Text(b.body).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(3).multilineTextAlignment(.leading) }
                                    }
                                    Spacer()
                                    let n = all.filter { $0.parentUUID == b.uuid }.count
                                    if n > 0 { Label("\(n)", systemImage: "arrow.triangle.branch").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted) }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete", role: .destructive) { context.delete(b); try? context.save() } }
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                            TextField("Grow it: a new thought from this idea…", text: $branch).textFieldStyle(.plain).font(Theme.ui(14))
                                .onSubmit(addBranch)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheetFrame(width: 680, height: 760)
        .sheet(item: $child) { IdeaSheet(idea: $0) }
    }

    private func touch() {
        idea.updatedAt = .now
        project?.updatedAt = .now
    }

    private func addBranch() {
        let t = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let project else { return }
        IdeaStore.add(t, to: project, under: idea, context: context)
        branch = ""
        touch()
    }

    /// Asks the assistant for a few directions this idea could go, added as branches you can keep or delete.
    private func grow() async {
        guard let project else { return }
        growing = true
        error = nil
        defer { growing = false }
        do {
            let found = try await IdeaStore.grow(idea, in: project, existing: branches.map(\.title))
            for g in found { IdeaStore.add(g.title, body: g.body, to: project, under: idea, context: context) }
            touch()
        } catch { self.error = error.localizedDescription }
    }
}

/// Make or edit a project.
private struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let project: IdeaProject?
    let saved: (IdeaProject) -> Void
    @State private var title = ""
    @State private var summary = ""
    @State private var color = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(project == nil ? "New project" : "Project").font(Theme.display(24))
            TextField("Name (e.g. My novel, Blog posts, The screenplay)", text: $title).textFieldStyle(.roundedBorder)
            TextField("What it's about (optional)", text: $summary, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            HStack(spacing: 8) {
                ForEach(0..<IdeasView.tints.count, id: \.self) { i in
                    Circle().fill(IdeasView.tints[i]).frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: color == i ? 2 : 0))
                        .onTapGesture { color = i }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Save") {
                    let p = project ?? IdeaStore.newProject(title, context: context)
                    p.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.colorIndex = color
                    p.updatedAt = .now
                    try? context.save()
                    saved(p)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).fixedSize()
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .sheetFrame(width: 460)
        .onAppear {
            title = project?.title ?? ""
            summary = project?.summary ?? ""
            color = project?.colorIndex ?? Int.random(in: 0..<IdeasView.tints.count)
        }
    }
}

/// Making projects and ideas (the Ideas tab and the assistant both use these).
@MainActor
enum IdeaStore {
    @discardableResult
    static func newProject(_ title: String, summary: String = "", context: ModelContext) -> IdeaProject {
        let p = IdeaProject(title: title, summary: summary)
        p.uuid = UUID().uuidString.lowercased()
        p.colorIndex = Int.random(in: 0..<IdeasView.tints.count)
        context.insert(p)
        return p
    }

    /// The project called `name` (loosely matched), made if it doesn't exist yet.
    static func project(named name: String, context: ModelContext) -> IdeaProject {
        let all = (try? context.fetch(FetchDescriptor<IdeaProject>())) ?? []
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let p = all.first(where: { $0.title.lowercased() == n }) ?? all.first(where: { !n.isEmpty && ($0.title.lowercased().contains(n) || n.contains($0.title.lowercased())) }) {
            return p
        }
        return newProject(name.isEmpty ? "Ideas" : name, context: context)
    }

    /// Adds an idea. A long text is split into a short title and the rest as its page.
    @discardableResult
    static func add(_ text: String, body: String = "", to project: IdeaProject, under parent: Idea? = nil, context: ModelContext) -> Idea {
        var title = text, rest = body
        if body.isEmpty, text.count > 90 {
            let firstSentence = text.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? text
            title = firstSentence.count <= 90 ? firstSentence : String(text.prefix(80)) + "…"
            rest = text
        }
        let idea = Idea(title: title.trimmingCharacters(in: .whitespaces), body: rest, projectUUID: project.uuid, parentUUID: parent?.uuid ?? "")
        idea.uuid = UUID().uuidString.lowercased()
        context.insert(idea)
        project.updatedAt = .now
        parent?.updatedAt = .now
        try? context.save()
        return idea
    }

    struct Growth: Decodable { let title: String; let body: String }

    /// A few directions the idea could grow in, from the assistant as a writing partner.
    static func grow(_ idea: Idea, in project: IdeaProject, existing: [String]) async throws -> [Growth] {
        guard let client = ClaudeClient() else { throw ClaudeClient.Failure.noKey }
        struct Out: Decodable { let branches: [Growth] }
        let out = try await client.structured(Out.self, system: """
            You're a writing partner helping a writer grow an idea for their project. Suggest 4 distinct directions the idea \
            could grow in: a twist, a deeper question, a character or detail, a scene or structure. Each has a short title \
            (under 10 words) and 1-3 sentences that make it concrete. Stay true to their tone and what they've written; \
            don't repeat what's already there. Write in the language they write in.
            """, user: """
            PROJECT: \(project.title)\(project.summary.isEmpty ? "" : " — \(project.summary)")
            IDEA: \(idea.title)
            WHAT THEY WROTE: \(idea.body.isEmpty ? "(nothing yet)" : String(idea.body.prefix(6000)))
            ALREADY GROWN FROM IT: \(existing.isEmpty ? "(nothing)" : existing.joined(separator: "; "))
            """,
            schema: ["type": "object", "additionalProperties": false, "required": ["branches"],
                     "properties": ["branches": ["type": "array", "items": [
                        "type": "object", "additionalProperties": false, "required": ["title", "body"],
                        "properties": ["title": ["type": "string"], "body": ["type": "string"]]]]]],
            effort: "medium")
        return Array(out.branches.prefix(5))
    }
}
