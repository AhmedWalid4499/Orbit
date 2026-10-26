import SwiftUI
import SwiftData

/// Passport, ID, licence, insurance, warranties… sorted by what expires first, with reminders before they do.
struct DocumentsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DocItem.createdAt) private var docs: [DocItem]
    @State private var editing: DocItem?
    @State private var adding = false
    @State private var kind: DocKind?

    private var sorted: [DocItem] {
        docs.filter { kind == nil || $0.kind == kind }
            .sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Documents", size: 38, isPage: true) {
                    Text("Joshu reminds you before anything expires. Keep numbers short (e.g. the last 4 digits).")
                        .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                } actions: {
                    Button { adding = true } label: { Label("Add document", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
                }
                summary
                filters
                if sorted.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 38, weight: .light))
                        Text("Add your passport, ID, driving licence, car registration and insurance. Warranties from order emails show up here by themselves.")
                            .font(Theme.ui(14)).multilineTextAlignment(.center)
                        Button("Add your first document") { adding = true }.buttonStyle(SoftButtonStyle())
                    }
                    .foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity).padding(.vertical, 50)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(sorted) { d in
                        DocCard(doc: d).onTapGesture { editing = d }
                            .contextMenu { Button("Delete", role: .destructive) { context.delete(d) } }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { DocEditor(doc: $0) }
        .sheet(isPresented: $adding) { DocEditor(doc: nil) }
    }

    private var summary: some View {
        let soon = docs.filter { ($0.daysLeft ?? 999) <= 90 && ($0.daysLeft ?? -1) >= 0 }.count
        let expired = docs.filter { ($0.daysLeft ?? 1) < 0 }.count
        return AdaptiveStack(grid: true) {
            tile("\(docs.count)", "Documents", Theme.cyan)
            tile("\(soon)", "Expire within 3 months", Theme.orange)
            tile("\(expired)", "Expired", expired > 0 ? Theme.pink : Theme.mint)
            tile("\(docs.filter { $0.kind == .warranty && ($0.daysLeft ?? -1) >= 0 }.count)", "Active warranties", Theme.lime)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", nil)
                ForEach(DocKind.allCases.filter { k in docs.contains { $0.kind == k } }) { chip($0.title, $0) }
                Spacer()
            }
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, _ k: DocKind?) -> some View {
        Button(title) { kind = k }
            .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(kind == k ? Theme.onInverse : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(kind == k ? Theme.inverse : Theme.card))
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

struct DocCard: View {
    let doc: DocItem
    @State private var hovering = false

    private var tint: Color {
        guard let d = doc.daysLeft else { return Theme.card }
        if d < 0 { return Theme.pink }
        if d <= doc.remindDays { return Theme.orange }
        if d <= 90 { return Theme.peach }
        return Theme.card
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: doc.kind.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 42, height: 42).background(Circle().fill(Color.white.opacity(0.6)))
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(Theme.ui(15, weight: .semibold)).lineLimit(2)
                Text([doc.kind.title, doc.issuer, doc.number.isEmpty ? "" : "•••\(doc.number.suffix(4))"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.ui(11)).opacity(0.7)
                if let e = doc.expires {
                    Text("Expires \(e.formatted(.dateTime.day().month(.abbreviated).year()))").font(Theme.ui(12, weight: .medium))
                } else {
                    Text("No expiry date").font(Theme.ui(12)).opacity(0.6)
                }
            }
            Spacer(minLength: 0)
            if let d = doc.daysLeft {
                VStack(spacing: 0) {
                    Text(d < 0 ? "!" : d >= 730 ? "\(d / 365)" : "\(d)").font(Theme.display(24))
                    Text(d < 0 ? "expired" : d >= 730 ? "years" : d == 1 ? "day" : "days").font(Theme.ui(10, weight: .semibold)).opacity(0.7)
                }
            }
        }
        .foregroundStyle(tint == Theme.card ? Theme.ink : Theme.stickerInk)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
        .scaleEffect(hovering ? 1.01 : 1)
        .onHover { hovering = $0 }
    }
}

struct DocEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let doc: DocItem?

    @State private var title = ""
    @State private var kind: DocKind = .passport
    @State private var number = ""
    @State private var issuer = ""
    @State private var hasExpiry = true
    @State private var expires = Date.now.adding(days: 365)
    @State private var remindDays = 30
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(doc == nil ? "New document" : "Edit document").font(Theme.display(26))
            FlowLayout(spacing: 6) {
                ForEach(DocKind.allCases) { k in
                    Label(k.title, systemImage: k.symbol).font(Theme.ui(12, weight: .medium))
                        .foregroundStyle(kind == k ? Theme.onInverse : Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(kind == k ? Theme.inverse : Theme.card))
                        .onTapGesture { kind = k; if title.isEmpty || DocKind.allCases.map(\.title).contains(title) { title = k.title } }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(Theme.inkSecondary); TextField("Egyptian passport", text: $title).textFieldStyle(.roundedBorder) }
                GridRow { Text("Issued by").foregroundStyle(Theme.inkSecondary); TextField("Authority, insurer, shop…", text: $issuer).textFieldStyle(.roundedBorder) }
                GridRow {
                    Text("Number").foregroundStyle(Theme.inkSecondary)
                    TextField("Last 4 digits is enough", text: $number).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Expires").foregroundStyle(Theme.inkSecondary)
                    HStack { Toggle("", isOn: $hasExpiry).labelsHidden(); if hasExpiry { DatePicker("", selection: $expires, displayedComponents: .date).labelsHidden() } }
                }
                GridRow {
                    Text("Remind me").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $remindDays) {
                        Text("1 week before").tag(7); Text("2 weeks before").tag(14); Text("1 month before").tag(30)
                        Text("2 months before").tag(60); Text("3 months before").tag(90); Text("6 months before").tag(180)
                    }
                    .labelsHidden().frame(width: 180)
                }
                GridRow { Text("Notes").foregroundStyle(Theme.inkSecondary); TextField("Where it's kept, how to renew…", text: $notes).textFieldStyle(.roundedBorder) }
            }
            .font(Theme.ui(13))
            Text("Passports often need 6 months of validity to travel, so a longer reminder helps.")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).opacity(kind == .passport ? 1 : 0)
            HStack {
                if let doc { Button("Delete", role: .destructive) { context.delete(doc); dismiss() }.buttonStyle(SoftButtonStyle()) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26).sheetFrame(width: 520)
        .onAppear {
            guard let d = doc else { title = DocKind.passport.title; remindDays = 180; return }
            title = d.title; kind = d.kind; number = d.number; issuer = d.issuer; remindDays = d.remindDays; notes = d.notes
            if let e = d.expires { expires = e } else { hasExpiry = false }
        }
        .onChange(of: kind) { if doc == nil { remindDays = kind == .passport || kind == .visa ? 180 : 30 } }
    }

    private func save() {
        let d = doc ?? { let d = DocItem(title: title); context.insert(d); return d }()
        d.title = title.trimmingCharacters(in: .whitespaces)
        d.kind = kind; d.number = number; d.issuer = issuer; d.notes = notes; d.remindDays = remindDays
        d.expires = hasExpiry ? expires.startOfDay : nil
        try? context.save()
        dismiss()
    }
}
