import Foundation

enum RecipeLayout: String, CaseIterable, Identifiable {
    case list, grid
    var id: Self { self }
    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}
