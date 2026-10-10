import Foundation

enum GroceryScope: String, CaseIterable, Identifiable {
    case all = "All", toBuy = "To Buy", completed = "Completed"
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .toBuy: "To buy"
        case .completed: "Checked"
        }
    }
}
