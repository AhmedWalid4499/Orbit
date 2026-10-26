import Foundation
import SwiftUI
import SwiftData
import Charts
#if os(iOS)
import HealthKit
#endif

/// Apple Health, read-only. The iPhone reads steps, sleep, active energy, workouts and resting heart rate, keeps a
/// short daily summary in the synced "health.daily" setting (so the Mac sees it too), and ticks off workout and walking
/// habits. Orbit never writes to Health.
@MainActor
final class HealthStore: ObservableObject {
    static let shared = HealthStore()

    struct Day: Codable, Equatable {
        var steps: Int = 0
        var activeKcal: Int = 0
        var sleepMinutes: Int = 0
        var workouts: Int = 0
        var workoutMinutes: Int = 0
        var restingHR: Int = 0
    }

    /// yyyy-MM-dd → that day's numbers, last 30 days.
    @Published private(set) var days: [String: Day] = [:]
    @Published private(set) var busy = false
    @Published var error: String?
    @AppStorage("health.connected") var connected = false

    static let key = "health.daily"

    private init() {
        if Snapshot.isDemo { days = Self.demo; return }
        load()
    }

    var available: Bool {
        #if os(iOS)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    var today: Day { days[DayKey.key(.now)] ?? Day() }
    var hasData: Bool { days.values.contains { $0 != Day() } }

    func load() {
        guard let s = UserDefaults.standard.string(forKey: Self.key), let data = s.data(using: .utf8),
              let d = try? JSONDecoder().decode([String: Day].self, from: data) else { return }
        days = d
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days), let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.key)
        }
    }

    func disconnect() {
        connected = false
        days = [:]
        // Emptied rather than removed, so other devices stop showing it too.
        UserDefaults.standard.set("", forKey: Self.key)
    }

    #if os(iOS)
    private let store = HKHealthStore()
    private var types: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.restingHeartRate),
         HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
    }

    func connect(context: ModelContext) async {
        guard available else { error = "Apple Health isn't available on this device."; return }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            connected = true
            await refresh(context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Reads the last 7 days (30 on the first run) and updates habits.
    func refresh(context: ModelContext) async {
        guard connected, available, !busy, !Snapshot.isActive else { return }
        busy = true
        defer { busy = false }
        let back = days.isEmpty ? 30 : 7
        let start = Date.now.startOfDay.adding(days: -back + 1)
        let steps = await daily(.stepCount, unit: .count(), from: start, sum: true)
        let kcal = await daily(.activeEnergyBurned, unit: .kilocalorie(), from: start, sum: true)
        let hr = await daily(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, sum: false)
        let sleep = await sleepByDay(from: start.adding(days: -1))
        let workouts = await workoutsByDay(from: start)
        for i in 0..<back {
            let day = start.adding(days: i), k = DayKey.key(day)
            var d = days[k] ?? Day()
            d.steps = Int(steps[k] ?? 0); d.activeKcal = Int(kcal[k] ?? 0); d.restingHR = Int(hr[k] ?? 0)
            d.sleepMinutes = sleep[k] ?? 0
            d.workouts = workouts[k]?.count ?? 0; d.workoutMinutes = workouts[k]?.minutes ?? 0
            days[k] = d
        }
        let cutoff = DayKey.key(.now.adding(days: -30))
        days = days.filter { $0.key >= cutoff }
        save()
        tickHabits(context: context)
    }

    private func daily(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, sum: Bool) async -> [String: Double] {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: .now))
        let q = HKStatisticsCollectionQueryDescriptor(predicate: predicate, options: sum ? .cumulativeSum : .discreteAverage,
                                                      anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let result = try? await q.result(for: store) else { return [:] }
        var out: [String: Double] = [:]
        result.enumerateStatistics(from: start, to: .now) { s, _ in
            let v = sum ? s.sumQuantity()?.doubleValue(for: unit) : s.averageQuantity()?.doubleValue(for: unit)
            if let v { out[DayKey.key(s.startDate)] = v }
        }
        return out
    }

    /// Minutes asleep, credited to the day you woke up.
    private func sleepByDay(from start: Date) async -> [String: Int] {
        let q = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                                                     predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
                                        sortDescriptors: [])
        guard let samples = try? await q.result(for: store) else { return [:] }
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
        // Several apps (Watch, AutoSleep, Oura…) record the same night: merge overlapping stretches before adding up.
        let spans = samples.filter { asleep.contains($0.value) }.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for s in spans {
            if let last = merged.last, s.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, s.1) } else { merged.append(s) }
        }
        var out: [String: Int] = [:]
        for (start, end) in merged { out[DayKey.key(end), default: 0] += Int(end.timeIntervalSince(start) / 60) }
        return out
    }

    private func workoutsByDay(from start: Date) async -> [String: (count: Int, minutes: Int)] {
        let q = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))], sortDescriptors: [])
        guard let list = try? await q.result(for: store) else { return [:] }
        var out: [String: (count: Int, minutes: Int)] = [:]
        for w in list {
            let k = DayKey.key(w.startDate)
            let cur = out[k] ?? (0, 0)
            out[k] = (cur.count + 1, cur.minutes + Int(w.duration / 60))
        }
        return out
    }
    #endif

    /// A workout in Health ticks off a workout-type habit, and 8,000+ steps a walking one, for that day.
    func tickHabits(context: ModelContext) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let workoutWords = ["workout", "gym", "exercise", "train", "run", "swim", "yoga", "cycle", "sport", "تمرين", "جيم"]
        let walkWords = ["walk", "steps", "مشي"]
        var ticked = Set(UserDefaults.standard.stringArray(forKey: "health.ticked") ?? [])
        func has(_ words: [String], _ name: String) -> Bool {
            let parts = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            return words.contains { parts.contains($0) || parts.contains($0 + "s") || parts.contains($0 + "ing") }
        }
        for day in (0..<7).map({ Date.now.startOfDay.adding(days: -$0) }) {
            guard let d = days[DayKey.key(day)] else { continue }
            for h in habits where !h.isDone(on: day) && day >= h.createdAt.startOfDay {
                // Ticked once already: you unticked it, so leave it.
                let mark = "\(h.uuid.isEmpty ? h.name : h.uuid)-\(DayKey.key(day))"
                guard !ticked.contains(mark) else { continue }
                if (d.workouts > 0 && has(workoutWords, h.name)) || (d.steps >= 8000 && has(walkWords, h.name)) {
                    h.toggle(day)
                    ticked.insert(mark)
                }
            }
        }
        UserDefaults.standard.set(Array(ticked.suffix(200)), forKey: "health.ticked")
        try? context.save()
    }

    /// For the assistant and the morning brief.
    func summary() -> String {
        guard hasData else { return "" }
        let last7 = (0..<7).compactMap { days[DayKey.key(.now.adding(days: -$0))] }
        let avgSteps = last7.isEmpty ? 0 : last7.reduce(0) { $0 + $1.steps } / last7.count
        let lastNight = today.sleepMinutes
        return "Apple Health: \(today.steps) steps today (7-day average \(avgSteps)); slept \(lastNight / 60)h \(lastNight % 60)m last night; "
            + "\(last7.reduce(0) { $0 + $1.workouts }) workouts this week; active energy today \(today.activeKcal) kcal"
            + (today.restingHR > 0 ? "; resting heart rate \(today.restingHR) bpm." : ".")
    }

    static let demo: [String: Day] = {
        var out: [String: Day] = [:]
        let steps = [8432, 5120, 11203, 6890, 9354, 4321, 7810]
        for i in 0..<7 {
            out[DayKey.key(.now.adding(days: -i))] = Day(steps: steps[i], activeKcal: 380 + i * 23, sleepMinutes: [412, 376, 455, 398, 430, 350, 401][i],
                                                          workouts: [1, 0, 1, 0, 1, 0, 0][i], workoutMinutes: [45, 0, 60, 0, 35, 0, 0][i], restingHR: 61 + i % 3)
        }
        return out
    }()
}

/// Steps, sleep, activity and workouts at a glance, with this week's steps (Insights, Mac and iPhone).
struct HealthCard: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var health = HealthStore.shared
    @AppStorage(HealthStore.key) private var raw = ""

    private struct Bar: Identifiable { let id: String; let day: Date; let steps: Int }
    private var week: [Bar] {
        (0..<7).reversed().map { i in
            let d = Date.now.startOfDay.adding(days: -i)
            return Bar(id: DayKey.key(d), day: d, steps: health.days[DayKey.key(d)]?.steps ?? 0)
        }
    }

    var body: some View {
        if health.hasData || health.connected {
            let t = health.today
            let workouts = (0..<7).compactMap { health.days[DayKey.key(.now.adding(days: -$0))] }.reduce(0) { $0 + $1.workouts }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    BrandLogo(brand: .appleHealth, size: 28)
                    Text("Health").font(Theme.display(22))
                    Spacer()
                    #if os(iOS)
                    if health.busy { ProgressView().controlSize(.small) }
                    Button { Task { await health.refresh(context: context) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
                    #else
                    Text("From your iPhone").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    #endif
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    stat("\(t.steps.formatted())", "Steps today", "figure.walk", Theme.mint)
                    stat(t.sleepMinutes > 0 ? "\(t.sleepMinutes / 60)h \(t.sleepMinutes % 60)m" : "—", "Sleep last night", "bed.double.fill", Theme.lavender)
                    stat("\(t.activeKcal)", "Active kcal", "flame.fill", Theme.orange)
                    stat("\(workouts)", "Workouts this week", "dumbbell.fill", Theme.cyan)
                }
                Chart(week) { b in
                    BarMark(x: .value("Day", b.day, unit: .day), y: .value("Steps", b.steps))
                        .foregroundStyle(b.steps >= 8000 ? Theme.mint : Theme.mint.opacity(0.45)).cornerRadius(5)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 110)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .task {
                #if os(iOS)
                await health.refresh(context: context)
                #else
                health.load()
                #endif
            }
            .onChange(of: raw) { health.load() }
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 30, height: 30).background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Theme.ui(16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
        }
    }
}

/// Settings › Connections › Apple Health.
struct HealthConnectionRow: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var health = HealthStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                BrandLogo(brand: .appleHealth, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health").font(.headline)
                    Text(Platform.isPhone
                         ? (health.connected ? "Steps, sleep, workouts and heart rate, in Insights. Workout habits tick themselves off." : "Read steps, sleep, workouts and heart rate. Joshu never writes to Health.")
                         : (health.hasData ? "Synced from your iPhone." : "Connect it in Joshu on your iPhone; the summary then shows here too."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                #if os(iOS)
                if health.connected {
                    Button("Disconnect", role: .destructive) { health.disconnect() }
                } else {
                    Button("Connect") { Task { await health.connect(context: context) } }.buttonStyle(.borderedProminent)
                }
                #endif
            }
            if let e = health.error { Text(e).font(.caption).foregroundStyle(Theme.orange) }
            #if os(iOS)
            if health.connected {
                Text("To stop sharing completely, also turn Joshu off in the Health app › Sharing › Apps.").font(.caption2).foregroundStyle(.secondary)
            }
            #endif
        }
    }
}
