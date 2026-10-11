import SwiftUI
import UniformTypeIdentifiers

/// A planned meal or note being dragged to another day.
nonisolated struct PlannedMealDrag: Codable, Transferable {
    let entryID: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plannedMeal)
    }
}
