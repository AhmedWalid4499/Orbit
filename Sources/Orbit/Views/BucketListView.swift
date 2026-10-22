import SwiftUI
import SwiftData

extension BucketKind {
    var color: Color {
        switch self {
        case .travel: Theme.cyan
        case .experience: Theme.pink
        case .adventure: Theme.orange
        case .learn: Theme.lime
        case .create: Theme.purple
        case .people: Theme.mint
        case .other: Theme.peach
        }
    }
}

/// Things you want to do in life, and the ones you're looking forward to.
struct BucketListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @Query(sort: \BucketItem.createdAt, order: .reverse) private var items: [BucketItem]

    @State private var show = "Dreams"
    @State private var kind: BucketKind?
    @State private var editing: BucketItem?
    @State private var adding = false
    @State private var openTrip: Trip?

    private var upcoming: [BucketItem] {
        items.filter { !$0.isDone && ($0.targetDate ?? .distantPast) >= Date.now.startOfDay }.sorted { $0.targetDate! < $1.targetDate! }
    }

    private var visible: [BucketItem] {
        items.filter { show == "Done" ? $0.isDone : !$0.isDone }
            .filter { kind == nil || $0.kind == kind }
            .sorted { show == "Done" ? ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) : $0.excitement > $1.excitement }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                TripsSection(open: $openTrip)
                if !upcoming.isEmpty { lookingForward }
                filters
                if visible.isEmpty { empty }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(visible) { item in
                        BucketCard(item: item) { openTrip = TripStore.plan(from: item, context: context) }
                            .onTapGesture { editing = item }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $adding) { BucketEditor(item: nil) }
        .sheet(item: $editing) { BucketEditor(item: $0) }
        .sheet(item: $openTrip) { TripSheet(trip: $0) }
    }

    private var header: some View {
        let done = items.filter(\.isDone).count
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bucket list").font(Theme.display(38))
                Text(items.isEmpty ? "The things you want to do, see, learn and feel." : "\(done) of \(items.count) done. Keep dreaming.")
                    .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if !items.isEmpty {
                ZStack {
                    Circle().stroke(Theme.card, lineWidth: 8)
                    Circle().trim(from: 0, to: items.isEmpty ? 0 : Double(done) / Double(items.count))
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(done)").font(Theme.display(18))
                }
                .frame(width: 54, height: 54)
            }
            Button { state.openAssistant(with: "Help me add some ideas to my bucket list. Ask me a couple of questions first.") } label: {
                Label("Ideas from \(AssistantName.current)", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
            Button { adding = true } label: { Label("Add dream", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
        }
    }

    private var lookingForward: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Looking forward to").font(Theme.display(22))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(upcoming) { item in
                        let days = Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: item.targetDate!.startOfDay).day ?? 0
                        HStack(spacing: 14) {
                            VStack(spacing: 0) {
                                Text(days == 0 ? "🎉" : "\(days)").font(Theme.display(days == 0 ? 30 : 34))
                                Text(days == 0 ? "today" : days == 1 ? "day" : "days").font(Theme.ui(11, weight: .semibold)).opacity(0.7)
                            }
                            .frame(width: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.kind.title, systemImage: item.kind.symbol).font(Theme.ui(11, weight: .semibold)).opacity(0.75)
                                Text(item.title).font(Theme.ui(15, weight: .semibold)).lineLimit(2)
                                Text(item.targetDate!.formatted(.dateTime.weekday(.wide).day().month())).font(Theme.ui(11)).opacity(0.7)
                            }
                            .frame(width: 180, alignment: .leading)
                        }
                        .foregroundStyle(Theme.stickerInk)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(item.kind.color))
                        .onTapGesture { editing = item }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ForEach(["Dreams", "Done"], id: \.self) { s in
                Button(s == "Done" ? "Done (\(items.filter(\.isDone).count))" : "Dreams (\(items.filter { !$0.isDone }.count))") { show = s }
                    .buttonStyle(.plain).font(Theme.ui(13, weight: .semibold))
                    .foregroundStyle(show == s ? Theme.onInverse : Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(show == s ? Theme.inverse : Theme.card))
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 4)
            ForEach(BucketKind.allCases) { k in
                Button { kind = kind == k ? nil : k } label: {
                    Label(k.title, systemImage: k.symbol).font(Theme.ui(12, weight: .medium))
                        .foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(k.color.opacity(kind == nil || kind == k ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "mountain.2").font(.system(size: 40, weight: .light))
            Text(show == "Done" ? "Nothing ticked off yet. Your first one is coming." : "What do you want to do one day? See the northern lights, learn Japanese, run a marathon…")
                .font(Theme.ui(14)).multilineTextAlignment(.center)
            if show != "Done" { Button("Add your first dream") { adding = true }.buttonStyle(SoftButtonStyle()) }
        }
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

private struct BucketCard: View {
    @Bindable var item: BucketItem
    var onTrip: () -> Void = {}
    @Query private var trips: [Trip]
    @State private var hovering = false
    @State private var celebrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.kind.symbol).font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.5)))
                Spacer()
                if item.kind == .travel && !item.isDone {
                    let planned = !item.uuid.isEmpty && trips.contains { $0.bucketUUID == item.uuid }
                    Button(action: onTrip) {
                        Label(planned ? "Trip" : "Plan trip", systemImage: "suitcase.fill")
                            .font(Theme.ui(12, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                }
                Text(String(repeating: "🔥", count: max(1, item.excitement))).font(.system(size: 12))
                    .help(["", "Nice to do", "Really want to", "Can't wait"][max(1, min(3, item.excitement))])
            }
            Text(item.title).font(Theme.display(20)).fixedSize(horizontal: false, vertical: true)
            if !item.notes.isEmpty { Text(item.notes).font(Theme.ui(12)).opacity(0.75).lineLimit(3) }
            HStack {
                if item.isDone, let d = item.doneAt {
                    Label("Done \(d.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "checkmark.seal.fill").font(Theme.ui(11, weight: .semibold))
                } else if let t = item.targetDate {
                    Label(t.formatted(.dateTime.day().month(.abbreviated).year()), systemImage: "calendar").font(Theme.ui(11, weight: .semibold))
                } else {
                    Text("Someday").font(Theme.ui(11, weight: .semibold)).opacity(0.6)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        item.isDone.toggle()
                        item.doneAt = item.isDone ? .now : nil
                        celebrate = item.isDone
                    }
                } label: {
                    Label(item.isDone ? "Done" : "Did it", systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(Theme.ui(12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(item.kind.color.opacity(item.isDone ? 0.55 : 1)))
        .overlay(alignment: .topTrailing) {
            if celebrate { Text("🎉").font(.system(size: 40)).offset(x: 10, y: -18).transition(.scale.combined(with: .opacity)) }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25), value: hovering)
        .onHover { hovering = $0 }
        .task(id: celebrate) {
            if celebrate { try? await Task.sleep(for: .seconds(1.5)); withAnimation { celebrate = false } }
        }
    }
}

private struct BucketEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let item: BucketItem?

    @State private var title = ""
    @State private var notes = ""
    @State private var kind: BucketKind = .experience
    @State private var hasDate = false
    @State private var date = Date.now.adding(days: 30)
    @State private var excitement = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item == nil ? "New dream" : "Edit").font(Theme.display(28))
            TextField("e.g. See the northern lights", text: $title)
                .textFieldStyle(.plain).font(Theme.ui(16))
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            FlowLayout(spacing: 6) {
                ForEach(BucketKind.allCases) { k in
                    Label(k.title, systemImage: k.symbol).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(k.color.opacity(kind == k ? 1 : 0.3)))
                        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: kind == k ? 1.5 : 0))
                        .onTapGesture { kind = k }
                }
            }
            HStack {
                Text("How much do you want it?").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                Picker("", selection: $excitement) {
                    Text("Nice to do").tag(1); Text("Really want to").tag(2); Text("Can't wait").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Toggle("I have a date in mind", isOn: $hasDate)
                if hasDate { DatePicker("", selection: $date, displayedComponents: .date).labelsHidden() }
            }
            .font(Theme.ui(13))
            TextField("Notes: why, who with, what it takes…", text: $notes, axis: .vertical)
                .textFieldStyle(.plain).font(Theme.ui(14)).lineLimit(3...6)
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            HStack {
                if let item {
                    Button("Delete", role: .destructive) { context.delete(item); dismiss() }.buttonStyle(SoftButtonStyle())
                } else {
                    Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button(item == nil ? "Add" : "Save", action: save)
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 120)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
        .onAppear {
            guard let item else { return }
            title = item.title; notes = item.notes; kind = item.kind; excitement = item.excitement
            if let d = item.targetDate { hasDate = true; date = d }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        if let item {
            item.title = t; item.notes = notes; item.kind = kind; item.excitement = excitement
            item.targetDate = hasDate ? date.startOfDay : nil
        } else {
            context.insert(BucketItem(title: t, kind: kind, notes: notes, targetDate: hasDate ? date.startOfDay : nil, excitement: excitement))
        }
        dismiss()
    }
}
