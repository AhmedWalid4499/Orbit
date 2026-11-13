import AppIntents
import Foundation
import WidgetKit

/// The areas offered in Settings › Focus › (a Focus) › Focus filters › Joshu.
enum FocusAreaOption: String, AppEnum {
    case work, personal, health, study, money, home, social

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Area"
    static var caseDisplayRepresentations: [FocusAreaOption: DisplayRepresentation] = [
        .work: DisplayRepresentation(title: "Work", image: .init(systemName: "briefcase.fill")),
        .personal: DisplayRepresentation(title: "Personal", image: .init(systemName: "sparkles")),
        .health: DisplayRepresentation(title: "Health", image: .init(systemName: "heart.fill")),
        .study: DisplayRepresentation(title: "Study", image: .init(systemName: "book.fill")),
        .money: DisplayRepresentation(title: "Money", image: .init(systemName: "dollarsign.circle.fill")),
        .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house.fill")),
        .social: DisplayRepresentation(title: "Social", image: .init(systemName: "person.2.fill")),
    ]
}

/// A Focus filter: while, say, Work Focus is on, Joshu's Today, Tasks and widgets show only Work tasks and habits.
/// iOS runs this when the Focus turns on (with your choice) and off (with nothing chosen, so everything shows again).
struct JoshuFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Choose what Joshu shows"
    static var description: IntentDescription? = IntentDescription("While this Focus is on, Joshu shows only tasks and habits from the areas you pick.")

    @Parameter(title: "Show only") var areas: [FocusAreaOption]?

    var displayRepresentation: DisplayRepresentation {
        let names = FocusAreas.names(Set((areas ?? []).compactMap { Area(rawValue: $0.rawValue) }))
        return DisplayRepresentation(title: names.isEmpty ? "Everything" : "Only \(names)")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set((areas ?? []).map(\.rawValue).joined(separator: ","), forKey: FocusAreas.key)
        await MainActor.run { WidgetActions.refreshWidgets() }
        return .result()
    }
}
