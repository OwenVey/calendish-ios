import ActivityKit
import Foundation

/// The Live Activities a cooking session shows. The system adapter drives ActivityKit; workflow tests record calls.
@MainActor
protocol CookingActivities {
    typealias Content = ActivityContent<CookingActivityAttributes.ContentState>
    /// Whether the person allows Live Activities for Calendish.
    var areEnabled: Bool { get }
    /// Whether an active or stale activity is showing for the session.
    func isShowing(session: UUID) -> Bool
    func start(_ attributes: CookingActivityAttributes, content: Content) throws
    func update(session: UUID, to content: Content) async
    /// The activities showing now, so ending them later can't end one a newer session started meanwhile.
    func showing() -> Set<String>
    /// Ends the given activities that belong to `session`, or any session when nil. A finished cook stays
    /// on the Lock Screen briefly with a closing message; anything else is removed immediately.
    func end(_ activities: Set<String>, session: UUID?, finished: Bool) async
}

struct SystemCookingActivities: CookingActivities {
    var areEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isShowing(session: UUID) -> Bool {
        Activity<CookingActivityAttributes>.activities.contains {
            $0.attributes.sessionID == session && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    func start(_ attributes: CookingActivityAttributes, content: Content) throws {
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(session: UUID, to content: Content) async {
        for activity in Activity<CookingActivityAttributes>.activities where activity.attributes.sessionID == session {
            await activity.update(content)
        }
    }

    func showing() -> Set<String> { Set(Activity<CookingActivityAttributes>.activities.map(\.id)) }

    func end(_ activities: Set<String>, session: UUID?, finished: Bool) async {
        for activity in Activity<CookingActivityAttributes>.activities where activities.contains(activity.id) {
            guard session == nil || activity.attributes.sessionID == session else { continue }
            var state = activity.content.state
            state.isFinished = finished
            if finished { state.instruction = "Enjoy your meal!" }
            await activity.end(ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: finished ? .after(.now.addingTimeInterval(60)) : .immediate)
        }
    }
}
