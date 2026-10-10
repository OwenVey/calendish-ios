import AppIntents
import Foundation

struct CookingTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Cooking Timer"
    static let isDiscoverable = false

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
