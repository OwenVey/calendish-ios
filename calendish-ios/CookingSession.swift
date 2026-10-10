import ActivityKit
import Foundation
import Observation

/// One cooking session owns both in-app navigation and the interactive Live Activity.
@MainActor @Observable
final class CookingSession {
    static let shared = CookingSession()

    struct Snapshot: Codable, Identifiable {
        var id = UUID()
        var recipe: Recipe
        var servings: Int
        var stepIndex = 0
        var startedAt = Date.now
        /// The recipe in the person's recipe book that finishing counts toward in cooked history.
        var cookedRecipeID: UUID?
    }

    private(set) var snapshot: Snapshot?
    private(set) var activityWarning: String?
    var stepIndex: Int { snapshot?.stepIndex ?? 0 }
    @ObservationIgnored private var photoLoad: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    private let storageKey = "cookingSession"
    private let accountKey = "cookingSessionAccountID"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           saved.startedAt > .now.addingTimeInterval(-8 * 3600),
           saved.recipe.steps.indices.contains(saved.stepIndex) {
            snapshot = saved
        }
    }

    /// Preserve an ongoing session across launches, while clearing private photos on account changes.
    func setAccount(_ accountID: UUID?) {
        let account = accountID?.uuidString
        guard account == nil || UserDefaults.standard.string(forKey: accountKey) != account else { return }
        end()
        CookingActivityPhoto.clear()
        if let account { UserDefaults.standard.set(account, forKey: accountKey) }
        else { UserDefaults.standard.removeObject(forKey: accountKey) }
    }

    func begin(recipe: Recipe, servings: Int, cookedRecipeID: UUID? = nil) {
        guard !recipe.steps.isEmpty else { return }
        if snapshot?.recipe.id != recipe.id {
            end()
            snapshot = Snapshot(recipe: recipe, servings: servings, cookedRecipeID: cookedRecipeID)
        }
        snapshot?.servings = servings
        persist()
        activityWarning = nil
        guard UserDefaults.standard.bool(forKey: PreferenceKey.liveActivity) else {
            // A session restored from before the setting was turned off may still have one.
            let id = snapshot?.id
            enqueue {
                for activity in Activity<CookingActivityAttributes>.activities where activity.attributes.sessionID == id {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activityWarning = "Live Activities are off. Allow them for Calendish in the Settings app."
            return
        }
        guard let snapshot else { return }
        preparePhoto(for: snapshot)
        if Activity<CookingActivityAttributes>.activities.contains(where: {
            $0.attributes.sessionID == snapshot.id && ($0.activityState == .active || $0.activityState == .stale)
        }) {
            refresh()
            return
        }
        do {
            let attributes = CookingActivityAttributes(sessionID: snapshot.id,
                recipeTitle: String(recipe.title.prefix(120)), stepCount: recipe.steps.count)
            _ = try Activity.request(attributes: attributes, content: content(for: snapshot), pushType: nil)
        } catch {
            activityWarning = "Couldn’t show the Live Activity. You can keep cooking here."
        }
    }

    func setStep(_ index: Int) {
        guard let snapshot, snapshot.recipe.steps.indices.contains(index) else { return }
        self.snapshot?.stepIndex = index
        persist()
        refresh()
    }

    func advance(sessionID: String, from index: Int) async {
        guard let snapshot, snapshot.id.uuidString == sessionID, snapshot.stepIndex == index else { return }
        if index == snapshot.recipe.steps.count - 1 { end(finished: true) }
        else { setStep(index + 1) }
        await pendingUpdate?.value
    }

    func startTimer(sessionID: String, at index: Int) async {
        guard snapshot?.id.uuidString == sessionID, snapshot?.stepIndex == index,
              case .started = startCurrentStepTimer() else { return }
        await CookingTimers.shared.schedulingTask?.value
        await pendingUpdate?.value
    }

    enum TimerStart: Equatable {
        case started(TimeInterval)
        case alreadyRunning
        case noDuration
    }

    /// Starts the current step's suggested timer, unless that step already has one running.
    func startCurrentStepTimer() -> TimerStart? {
        guard let snapshot else { return nil }
        let index = snapshot.stepIndex
        guard let duration = CookTimer.duration(in: snapshot.recipe.steps[index]) else { return .noDuration }
        guard !CookingTimers.shared.timers.contains(where: { $0.recipeID == snapshot.recipe.id && $0.stepIndex == index }) else {
            return .alreadyRunning
        }
        CookingTimers.shared.start(recipe: snapshot.recipe, stepIndex: index, duration: duration)
        return .started(duration)
    }

    func refresh() {
        guard let snapshot else { return }
        let content = content(for: snapshot)
        enqueue {
            for activity in Activity<CookingActivityAttributes>.activities where activity.attributes.sessionID == snapshot.id {
                await activity.update(content)
            }
        }
    }

    func end(finished: Bool = false) {
        photoLoad?.cancel()
        photoLoad = nil
        let previous = snapshot
        // Only activities running now; one started later belongs to a new session.
        let activityIDs = Set(Activity<CookingActivityAttributes>.activities.map(\.id))
        snapshot = nil
        persist()
        // Every way of finishing, in the app or from the Live Activity, counts toward cooked history.
        if finished, let previous, let recipeID = previous.cookedRecipeID {
            FinishedCooks.shared.add(FinishedCook(recipeID: recipeID, startedAt: previous.startedAt,
                accountID: UserDefaults.standard.string(forKey: accountKey).flatMap(UUID.init)))
        }
        activityWarning = nil
        enqueue {
            for activity in Activity<CookingActivityAttributes>.activities where activityIDs.contains(activity.id) {
                // Capture the session before awaiting so a newly started activity isn't ended.
                guard previous == nil || activity.attributes.sessionID == previous?.id else { continue }
                var state = activity.content.state
                state.isFinished = finished
                if finished { state.instruction = "Enjoy your meal!" }
                await activity.end(ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: finished ? .after(.now.addingTimeInterval(60)) : .immediate)
            }
        }
    }

    private func content(for snapshot: Snapshot) -> ActivityContent<CookingActivityAttributes.ContentState> {
        let timer = CookingTimers.shared.timers
            .filter { $0.recipeID == snapshot.recipe.id }
            .min { $0.end < $1.end }
        let step = snapshot.recipe.steps[snapshot.stepIndex]
        let state = CookingActivityAttributes.ContentState(stepIndex: snapshot.stepIndex,
            recipeImageName: CookingActivityPhoto.image(named: snapshot.id.uuidString) == nil ? nil : snapshot.id.uuidString,
            instruction: String(step.prefix(600)), timerStart: timer.map { $0.end.addingTimeInterval(-$0.duration) }, timerEnd: timer?.end, timerStepIndex: timer?.stepIndex,
            suggestedDuration: CookTimer.duration(in: step))
        return ActivityContent(state: state, staleDate: timer?.end ?? snapshot.startedAt.addingTimeInterval(8 * 3600))
    }

    private func preparePhoto(for snapshot: Snapshot) {
        CookingActivityPhoto.prune(keeping: snapshot.id)
        guard let path = snapshot.recipe.imagePath,
              CookingActivityPhoto.image(named: snapshot.id.uuidString) == nil else { return }
        photoLoad?.cancel()
        photoLoad = Task {
            guard let image = await RecipePhotos.shared.image(for: path, thumbnail: true),
                  !Task.isCancelled, self.snapshot?.id == snapshot.id else { return }
            do {
                try CookingActivityPhoto.save(image, for: snapshot.id)
                refresh()
            } catch {
                // Cooking remains available when a thumbnail can't be cached.
            }
        }
    }

    private func persist() {
        if let snapshot { UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: storageKey) }
        else { UserDefaults.standard.removeObject(forKey: storageKey) }
    }

    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = pendingUpdate
        pendingUpdate = Task {
            await previous?.value
            await action()
        }
    }
}
