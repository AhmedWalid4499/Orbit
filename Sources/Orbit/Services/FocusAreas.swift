import Foundation

/// The areas an iPhone Focus asks Joshu to show (Settings › Focus › Work › Focus filters › Joshu).
/// Empty means everything. Set by JoshuFocusFilter (iOS/OrbitPhone/FocusFilter.swift); read by Today, Tasks and the widgets.
enum FocusAreas {
    static let key = "focusFilter.areas"

    static func parse(_ raw: String) -> Set<Area> {
        Set(raw.split(separator: ",").compactMap { Area(rawValue: String($0)) })
    }

    static var current: Set<Area> { parse(UserDefaults.standard.string(forKey: key) ?? "") }

    static func allows(_ area: Area, in shown: Set<Area>) -> Bool { shown.isEmpty || shown.contains(area) }

    /// "Work", "Work and Health", "Work, Health and Home".
    static func names(_ shown: Set<Area>) -> String {
        let titles = Area.allCases.filter(shown.contains).map(\.title)
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " and " + titles.last!
    }
}
