import Foundation

enum RecipeSort: String, CaseIterable, Identifiable {
    case recent, title, rating, recentlyCooked, leastRecentlyCooked
    var id: Self { self }
    var title: String {
        switch self {
        case .recent: "Recently added"
        case .title: "Title A–Z"
        case .rating: "Highest rated"
        case .recentlyCooked: "Recently cooked or planned"
        case .leastRecentlyCooked: "Least recently cooked or planned"
        }
    }
    var showsLastCooked: Bool { self == .recentlyCooked || self == .leastRecentlyCooked }

    /// Sorts recipes already in Recently Added order. Ties keep that order; never-cooked recipes count as
    /// cooked longest ago, and unrated recipes come after rated ones.
    func sorted(_ recipes: [Recipe], stats: [UUID: RecipeStats]) -> [Recipe] {
        switch self {
        case .recent: recipes
        case .title: recipes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .rating:
            recipes.enumerated().sorted { a, b in
                let ra = stats[a.element.id]?.averageRating ?? 0, rb = stats[b.element.id]?.averageRating ?? 0
                return ra != rb ? ra > rb : a.offset < b.offset
            }.map(\.element)
        case .recentlyCooked, .leastRecentlyCooked:
            recipes.enumerated().sorted { a, b in
                let da = stats[a.element.id]?.history.lastCooked ?? .distantPast, db = stats[b.element.id]?.history.lastCooked ?? .distantPast
                guard da != db else { return a.offset < b.offset }
                return self == .recentlyCooked ? da > db : da < db
            }.map(\.element)
        }
    }
}
