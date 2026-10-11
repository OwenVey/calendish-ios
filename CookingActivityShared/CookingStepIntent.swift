import AppIntents
import Foundation

struct CookingStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Cooking Step"
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Step") var stepIndex: Int

    init() { }
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
