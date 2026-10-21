import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var adding = false

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Habits").font(Theme.display(38))
                    Spacer()
                    Button { adding = true } label: { Label("New habit", systemImage: "plus") }
                        .buttonStyle(SoftButtonStyle())
                }
                if habits.isEmpty {
                    EmptyHint(symbol: "repeat", text: "Small daily wins add up. Add your first habit.")
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(habits) { HabitCard(habit: $0) }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $adding) { NewHabitSheet() }
    }
}

private struct HabitCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var habit: Habit

    private let weeks = 18

    var body: some View {
        let today = Date.now.startOfDay
        let last7 = (0..<7).map { today.adding(days: $0 - 6) }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: habit.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.55)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(Theme.ui(17, weight: .semibold))
                    Text("\(habit.doneThisWeek) of \(habit.targetPerWeek) this week").font(Theme.ui(12)).opacity(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(habit.currentStreak)").font(Theme.display(44))
                    Text("day streak").font(Theme.ui(11, weight: .medium)).opacity(0.7)
                }
            }

            HStack(spacing: 8) {
                ForEach(last7, id: \.self) { day in
                    let done = habit.isDone(on: day)
                    Button { withAnimation(.snappy) { habit.toggle(day) } } label: {
                        VStack(spacing: 6) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(Theme.ui(11, weight: .medium)).opacity(0.7)
                            ZStack {
                                Circle().fill(done ? Color(hex: 0x111111) : Color.white.opacity(0.55))
                                if done {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(habit.area.color)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color(hex: 0x111111), lineWidth: day.isToday ? 1.5 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }

            heatmap
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(habit.area.color))
        .contextMenu {
            Stepper("Target: \(habit.targetPerWeek)/week", value: $habit.targetPerWeek, in: 1...7)
            Menu("Area") { ForEach(Area.allCases) { a in Button(a.title) { habit.area = a } } }
            Divider()
            Button("Delete habit", role: .destructive) { context.delete(habit) }
        }
    }

    /// Last N weeks as a contribution grid. Single hue, light→dark: done vs not done.
    private var heatmap: some View {
        let start = Date.now.startOfWeek.adding(days: -7 * (weeks - 1))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last \(weeks) weeks").font(Theme.ui(11, weight: .medium)).opacity(0.7)
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = start.adding(days: w * 7 + d)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(day > .now ? Color.clear :
                                        habit.isDone(on: day) ? Color(hex: 0x111111).opacity(0.85) : Color.white.opacity(0.45))
                                .aspectRatio(1, contentMode: .fit)
                                .help("\(day.formatted(date: .abbreviated, time: .omitted)) — \(habit.isDone(on: day) ? "done" : "missed")")
                        }
                    }
                }
            }
        }
    }
}

private struct NewHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var area: Area = .health
    @State private var target = 7
    @State private var symbol = "checkmark"

    private let symbols = ["checkmark", "figure.run", "book.fill", "drop.fill", "bed.double.fill", "leaf.fill",
                           "brain.head.profile", "creditcard", "fork.knife", "dumbbell.fill", "pencil", "moon.stars.fill",
                           "phone.down.fill", "sun.max.fill", "music.note", "heart.fill"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New habit").font(Theme.display(28))
            TextField("e.g. Meditate 10 minutes", text: $name)
                .textFieldStyle(.plain).font(Theme.ui(16))
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8), spacing: 8) {
                ForEach(symbols, id: \.self) { s in
                    Image(systemName: s)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(symbol == s ? area.color : Theme.card))
                        .foregroundStyle(symbol == s ? Theme.stickerInk : Theme.ink)
                        .onTapGesture { symbol = s }
                }
            }
            AreaPicker(selection: $area)
            Stepper("Target: \(target) days a week", value: $target, in: 1...7).font(Theme.ui(13))
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Add habit") {
                    context.insert(Habit(name: name, symbol: symbol, area: area, targetPerWeek: target))
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 140)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}
