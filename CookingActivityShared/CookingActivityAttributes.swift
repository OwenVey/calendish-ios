import ActivityKit
import AppIntents
import Foundation

nonisolated struct CookingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepIndex: Int
        var recipeImageName: String?
        var instruction: String
        var timerStart: Date?
        var timerEnd: Date?
        var timerStepIndex: Int?
        var suggestedDuration: TimeInterval?
        var isFinished = false
    }

    var sessionID: UUID
    var recipeTitle: String
    var stepCount: Int

    var cookingURL: URL { URL(string: "calendish://cooking/\(sessionID.uuidString)")! }
}
