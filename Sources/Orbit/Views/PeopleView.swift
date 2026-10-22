import SwiftUI
import SwiftData

/// Birthdays coming up, people you haven't talked to in a while, gift ideas, and everyone in one place.
struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @Query(sort: \Person.name) private var people: [Person]
    @ObservedObject private var store = PeopleStore.shared
    @ObservedObject private var inbox = InboxStore.shared
    @State private var editing: Person?
    @State private var adding = false
    @State private var importing = false
    @State private var relation: Relation?

    private var birthdays: [Person] {
        people.filter { ($0.nextBirthday ?? .distantFuture) < Date.now.adding(days: 60) }
            .sorted { ($0.nextBirthday ?? .distantFuture) < ($1.nextBirthday ?? .distantFuture) }
    }
    private var reachOut: [Person] {
        people.filter(\.overdueForContact).sorted { ($0.lastContact ?? .distantPast) < ($1.lastContact ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(spacing: 12) {
                    tile("\(people.count)", "People", Theme.cyan)
                    tile("\(people.filter { ($0.nextBirthday ?? .distantFuture) < Date.now.adding(days: 30) }.count)", "Birthdays in 30 days", Theme.pink)
                    tile("\(reachOut.count)", "To reach out to", Theme.orange)
                    tile("\(people.reduce(0) { $0 + $1.giftIdeas.count })", "Gift ideas", Theme.lime)
                }
                if !birthdays.isEmpty { birthdaySection }
                if !reachOut.isEmpty { reachOutSection }
                everyone
            }
            .padding(.horizontal, 32).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { PersonEditor(person: $0) }
        .sheet(isPresented: $adding) { PersonEditor(person: nil) }
        .sheet(isPresented: $importing) { ContactsImportSheet() }
        .task { await store.refreshIfDue(context: context) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("People").font(Theme.display(38))
                Text("Birthdays, gift ideas, and a nudge when it's been too long.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if inbox.isConnected {
                Button { Task { await store.refreshLastContact(context: context) } } label: {
                    Label(store.checking ? "Checking email…" : "Check email", systemImage: "envelope.arrow.triangle.branch")
                }
                .buttonStyle(SoftButtonStyle()).disabled(store.checking)
                .help("Find when you last emailed each person")
            }
            Button { importing = true } label: { Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus") }
                .buttonStyle(SoftButtonStyle())
            Button { adding = true } label: { Label("Add person", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
        }
    }

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Birthdays coming up").font(Theme.display(22))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(birthdays) { p in
                        let days = Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: p.nextBirthday!).day ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(Theme.ui(15, weight: .semibold)).lineLimit(1)
                                    Text(p.nextBirthday!.formatted(.dateTime.weekday(.wide).day().month()) + (p.turningAge.map { " · turns \($0)" } ?? ""))
                                        .font(Theme.ui(11)).opacity(0.75)
                                }
                                Spacer()
                                VStack(spacing: 0) {
                                    Text(days == 0 ? "🎂" : "\(days)").font(Theme.display(days == 0 ? 26 : 30))
                                    if days > 0 { Text(days == 1 ? "day" : "days").font(Theme.ui(10, weight: .semibold)).opacity(0.7) }
                                }
                            }
                            if p.giftIdeas.isEmpty {
                                Button { state.openAssistant(with: giftPrompt(p)) } label: { Label("Gift ideas from \(AssistantName.current)", systemImage: "gift") }
                                    .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                            } else {
                                Label(p.giftIdeas.prefix(2).joined(separator: " · "), systemImage: "gift").font(Theme.ui(12)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(Theme.stickerInk)
                        .padding(16).frame(width: 260, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20).fill(days <= 7 ? Theme.pink : Theme.peach))
                        .onTapGesture { editing = p }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var reachOutSection: some View {
        Card(fill: Theme.blush) {
            VStack(alignment: .leading, spacing: 10) {
                Text("It's been a while").font(Theme.display(20))
                ForEach(reachOut.prefix(6)) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(Theme.ui(14, weight: .semibold))
                            Text(p.lastContact.map { "Last talked \($0.formatted(.relative(presentation: .named)))" } ?? "No contact logged yet")
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                        if !p.email.isEmpty, let url = URL(string: "mailto:\(p.email.split(separator: ",").first ?? "")") {
                            Link(destination: url) { Image(systemName: "envelope") }.help("Email \(p.name)")
                        }
                        if !p.phone.isEmpty, let url = URL(string: "sms:\(p.phone.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: url) { Image(systemName: "message") }.help("Message \(p.name)")
                        }
                        Button("Talked today") { p.lastContact = .now; p.lastContactSource = "manual" }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
    }

    private var everyone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Everyone").font(Theme.display(22)).padding(.trailing, 8)
                chip("All", nil)
                ForEach(Relation.allCases) { r in if people.contains(where: { $0.relation == r }) { chip(r.title, r) } }
                Spacer()
            }
            if people.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2").font(.system(size: 38, weight: .light))
                    Text("Add the people who matter, or import them from Contacts with their birthdays.").font(Theme.ui(14))
                    HStack {
                        Button("Import from Contacts") { importing = true }.buttonStyle(SoftButtonStyle())
                        Button("Add person") { adding = true }.buttonStyle(SoftButtonStyle())
                    }
                }
                .foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(people.filter { relation == nil || $0.relation == relation }) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                            Text([p.relation.title, p.birthday.map { "🎂 " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 0)
                        if p.overdueForContact { Circle().fill(Theme.orange).frame(width: 8, height: 8).help("Time to reach out") }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                    .contentShape(Rectangle())
                    .onTapGesture { editing = p }
                    .contextMenu { Button("Delete", role: .destructive) { context.delete(p) } }
                }
            }
        }
    }

    private func chip(_ title: String, _ r: Relation?) -> some View {
        Button(title) { relation = r }
            .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(relation == r ? Theme.onInverse : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(relation == r ? Theme.inverse : Theme.card))
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(26))
            Text(label).font(Theme.ui(12, weight: .semibold)).opacity(0.8).lineLimit(1)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(color))
    }
}

func giftPrompt(_ p: Person) -> String {
    var s = "Help me with gift ideas for \(p.name) (\(p.relation.title.lowercased()))"
    if let next = p.nextBirthday { s += ", whose birthday is \(next.formatted(.dateTime.day().month(.wide)))" }
    if !p.notes.isEmpty { s += ". About them: \(p.notes)" }
    if !p.giftIdeas.isEmpty { s += ". Ideas I already have: \(p.giftIdeas.joined(separator: ", "))" }
    return s + ". Ask me a question or two first, then save the best ideas to their gift list."
}

struct PersonEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    let person: Person?

    @State private var name = ""
    @State private var relation: Relation = .friend
    @State private var email = ""
    @State private var phone = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1))!
    @State private var yearKnown = true
    @State private var every = 0
    @State private var gifts: [String] = []
    @State private var newGift = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(person == nil ? "New person" : name).font(Theme.display(26))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(Theme.inkSecondary); TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
                GridRow {
                    Text("Who").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $relation) { ForEach(Relation.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                }
                GridRow { Text("Email").foregroundStyle(Theme.inkSecondary); TextField("Used to find when you last talked", text: $email).textFieldStyle(.roundedBorder) }
                GridRow { Text("Phone").foregroundStyle(Theme.inkSecondary); TextField("", text: $phone).textFieldStyle(.roundedBorder) }
                GridRow {
                    Text("Birthday").foregroundStyle(Theme.inkSecondary)
                    HStack {
                        Toggle("", isOn: $hasBirthday).labelsHidden()
                        if hasBirthday {
                            DatePicker("", selection: $birthday, displayedComponents: .date).labelsHidden()
                            Toggle("Year known", isOn: $yearKnown).font(Theme.ui(11))
                        }
                    }
                }
                GridRow {
                    Text("Keep in touch").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $every) {
                        Text("No reminder").tag(0); Text("Every 2 weeks").tag(14); Text("Every month").tag(30)
                        Text("Every 2 months").tag(60); Text("Every 3 months").tag(90); Text("Every 6 months").tag(180)
                    }
                    .labelsHidden().frame(width: 170)
                }
            }
            .font(Theme.ui(13))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Gift ideas").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if person != nil {
                        Button("Ask \(AssistantName.current)") {
                            if let person { dismiss(); state.openAssistant(with: giftPrompt(person)) }
                        }
                        .buttonStyle(.link).font(Theme.ui(11))
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(gifts, id: \.self) { g in
                        HStack(spacing: 4) {
                            Text(g)
                            Button { gifts.removeAll { $0 == g } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                        }
                        .font(Theme.ui(12)).padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.stickerInk)
                    }
                }
                TextField("Add an idea and press Return", text: $newGift).textFieldStyle(.roundedBorder)
                    .onSubmit { let g = newGift.trimmingCharacters(in: .whitespaces); if !g.isEmpty { gifts.append(g) }; newGift = "" }
            }
            TextField("Notes: likes, sizes, kids' names…", text: $notes, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            HStack {
                if let person { Button("Delete", role: .destructive) { context.delete(person); dismiss() }.buttonStyle(SoftButtonStyle()) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26).frame(width: 540)
        .onAppear {
            guard let p = person else { return }
            name = p.name; relation = p.relation; email = p.email; phone = p.phone; every = p.contactEveryDays
            gifts = p.giftIdeas; notes = p.notes
            if let b = p.birthday { hasBirthday = true; birthday = b; yearKnown = Calendar.current.component(.year, from: b) > 1900 }
        }
    }

    private func save() {
        let p = person ?? { let p = Person(name: name); context.insert(p); return p }()
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.relation = relation; p.email = email; p.phone = phone; p.contactEveryDays = every; p.notes = notes
        p.giftIdeas = gifts + (newGift.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [newGift.trimmingCharacters(in: .whitespaces)])
        if hasBirthday {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
            if !yearKnown { c.year = 1 }
            p.birthday = Calendar(identifier: .gregorian).date(from: c)
        } else {
            p.birthday = nil
        }
        try? context.save()
        dismiss()
    }
}

private struct ContactsImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var rows: [PeopleStore.ContactRow] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Contacts").font(Theme.display(26))
            Text("Pick the people you want in Orbit. Birthdays, emails and phone numbers come along.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            HStack {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Button("Everyone with a birthday") { selected = Set(rows.filter { $0.birthday != nil }.map(\.id)) }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange) }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            List(rows.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { r in
                Toggle(isOn: Binding(get: { selected.contains(r.id) }, set: { if $0 { selected.insert(r.id) } else { selected.remove(r.id) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name)
                        Text([r.birthday.map { "🎂 " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "", r.email].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 340)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Import \(selected.count)") {
                    _ = PeopleStore.shared.importContacts(rows.filter { selected.contains($0.id) }, context: context)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 130).disabled(selected.isEmpty)
            }
        }
        .padding(26).frame(width: 520)
        .task {
            do { rows = try await PeopleStore.shared.loadContacts() } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
