import SwiftUI

/// Tasks › Shared lists: lists you share with other Orbit users by a six-letter code. Changes show up for everyone
/// within a few seconds while the list is open.
struct SharedListsView: View {
    @ObservedObject private var store = SharedListStore.shared
    @ObservedObject private var cloud = CloudSync.shared
    @State private var newTitle = ""
    @State private var joining = false
    @State private var code = ""
    @State private var openID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.isAvailable {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Sign in to share lists", systemImage: "person.2.fill").font(Theme.ui(15, weight: .semibold))
                        Text("Shared lists go through your Orbit account. Sign in under Settings › Account, then make a list and send its code to anyone with Orbit.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                        TextField("New shared list: Groceries, Dahab trip…", text: $newTitle)
                            .textFieldStyle(.plain).font(Theme.ui(15)).onSubmit(create)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    Button { joining.toggle() } label: { Label("Join", systemImage: "person.badge.plus") }.buttonStyle(SoftButtonStyle())
                }
                if joining {
                    HStack(spacing: 10) {
                        TextField("Code from the invite", text: $code)
                            .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                            #if os(iOS)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            #endif
                            .onSubmit(join)
                        Button("Join list", action: join).buttonStyle(PrimaryButtonStyle()).fixedSize()
                            .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                    }
                }
                if let e = store.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.lists.isEmpty && !store.loading {
                    EmptyHint(symbol: "person.2", text: "No shared lists yet. Make one above, or join with a code.")
                }
                ForEach(store.lists) { list in
                    // The first list starts open.
                    let open = openID == list.id || (openID == nil && list.id == store.lists.first?.id)
                    SharedListCard(list: list, expanded: open) {
                        withAnimation(.snappy) { openID = open ? "" : list.id }
                    }
                }
            }
        }
        .task(id: cloud.isSignedIn) {
            // Keep the lists fresh while they're on screen.
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func create() {
        let t = newTitle
        newTitle = ""
        Task { if let l = await store.create(t) { openID = l.id } }
    }

    private func join() {
        Task { if await store.join(code: code) { code = ""; joining = false } }
    }
}

struct SharedListCard: View {
    @ObservedObject private var store = SharedListStore.shared
    let list: SharedList
    let expanded: Bool
    let toggle: () -> Void
    @State private var draft = ""
    @State private var confirmLeave = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.stickerInk).frame(width: 30, height: 30).background(Circle().fill(Theme.mint))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(list.title).font(Theme.ui(16, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text("\(list.openCount) to do · \(list.memberCount) \(list.memberCount == 1 ? "person" : "people")")
                                .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Theme.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(list.items) { item in
                        HStack(spacing: 10) {
                            Button {
                                var i = item; i.done.toggle()
                                Task { await store.put(i, in: list) }
                            } label: { CheckCircle(isOn: item.done, size: 18) }
                            .buttonStyle(.plain)
                            Text(item.text).font(Theme.ui(14)).strikethrough(item.done).foregroundStyle(item.done ? Theme.inkMuted : Theme.ink)
                            Spacer()
                            if !item.by.isEmpty { Text(item.by).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted) }
                            Button { Task { await store.remove(item, from: list) } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                        TextField("Add an item", text: $draft).textFieldStyle(.plain).font(Theme.ui(14)).onSubmit(add)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.canvas))
                    HStack(spacing: 8) {
                        ShareLink(item: list.inviteText) { Label("Invite · \(list.code)", systemImage: "square.and.arrow.up") }
                            .buttonStyle(SoftButtonStyle())
                        Button { Platform.copy(list.code) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(SoftButtonStyle()).help("Copy the code")
                        Spacer()
                        if list.items.contains(where: \.done) {
                            Button("Clear done") { Task { await store.clearDone(list) } }.buttonStyle(SoftButtonStyle())
                        }
                        Button(list.isMine ? "Delete" : "Leave", role: .destructive) { confirmLeave = true }.buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
        .confirmationDialog(list.isMine ? "Delete “\(list.title)” for everyone?" : "Leave “\(list.title)”?", isPresented: $confirmLeave) {
            Button(list.isMine ? "Delete list" : "Leave list", role: .destructive) { Task { await store.leave(list) } }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        draft = ""
        Task { await store.put(.init(text: t, by: SharedListStore.me), in: list) }
    }
}

/// Settings › AI: what the assistant remembers about you, to read, add to or remove.
struct MemorySection: View {
    @State private var items = AssistantMemory.items
    @State private var draft = ""

    var body: some View {
        Section {
            if items.isEmpty {
                Text("Nothing yet. Tell \(AssistantName.current) things like “I'm vegetarian” or “I go to the gym on Tuesdays” and it'll remember.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(items, id: \.self) { fact in
                HStack {
                    Text(fact)
                    Spacer()
                    Button { AssistantMemory.forget(fact); items = AssistantMemory.items } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Forget this")
                }
            }
            HStack {
                TextField("Add something to remember", text: $draft).onSubmit(add)
                Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !items.isEmpty {
                Button("Forget everything", role: .destructive) { AssistantMemory.items = []; items = [] }
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("\(AssistantName.current) remembers lasting things you tell it (preferences, routines, people) and uses them in every chat. It's kept with your settings and synced to your devices.")
        }
        .onAppear { items = AssistantMemory.items }
    }

    private func add() {
        AssistantMemory.remember(draft)
        draft = ""
        items = AssistantMemory.items
    }
}
