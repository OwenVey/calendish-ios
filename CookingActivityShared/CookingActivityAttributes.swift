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

struct CookingStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Cooking Step"
    static var isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Step") var stepIndex: Int

    init() {}
    init(sessionID: UUID, stepIndex: Int) {
        self.sessionID = sessionID.uuidString
        self.stepIndex = stepIndex
    }

    func perform() async throws -> some IntentResult {
        #if CALENDISH_APP
        await CookingSession.shared.advance(sessionID: sessionID, from: stepIndex)
        #endif
        return .result()
    }
}

struct CookingTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Cooking Timer"
    static var isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Step") var stepIndex: Int

    init() {}
    init(sessionID: UUID, stepIndex: Int) {
        self.sessionID = sessionID.uuidString
        self.stepIndex = stepIndex
    }

    func perform() async throws -> some IntentResult {
        #if CALENDISH_APP
        await CookingSession.shared.startTimer(sessionID: sessionID, at: stepIndex)
        #endif
        return .result()
    }
}
