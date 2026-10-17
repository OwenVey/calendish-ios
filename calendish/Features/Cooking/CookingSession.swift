import ActivityKit
import Foundation
import Observation

/// One cooking session owns in-app navigation, its step timers, the interactive Live Activity, and recording
/// a finished cook. The app and Live Activity intents share `shared`; tests build their own with controlled dependencies.
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
    /// Where cooking left off when Cook Mode closed with timers still running, so it can pick up there.
    private(set) var paused: Snapshot?
    private(set) var activityWarning: String?
    var stepIndex: Int { snapshot?.stepIndex ?? 0 }
    /// Every running step timer. Their changes update the Live Activity.
    let timers: CookingTimers
    @ObservationIgnored private let finishedCooks: FinishedCooks
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let activities: any CookingActivities
    @ObservationIgnored private var photoLoad: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    private let storageKey = "cookingSession"
    private let accountKey = "cookingSessionAccountID"
    private let pausedKey = "pausedCookingSession"

    init(timers: CookingTimers = CookingTimers(), finishedCooks: FinishedCooks = .shared,
         defaults: UserDefaults = .standard, activities: any CookingActivities = SystemCookingActivities()) {
        self.timers = timers
        self.finishedCooks = finishedCooks
        self.defaults = defaults
        self.activities = activities
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           saved.startedAt > .now.addingTimeInterval(-8 * 3600),
           saved.recipe.steps.indices.contains(saved.stepIndex) {
            snapshot = saved
        }
        if let data = defaults.data(forKey: pausedKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           saved.startedAt > .now.addingTimeInterval(-8 * 3600),
           saved.recipe.steps.indices.contains(saved.stepIndex) {
            paused = saved
        }
        timers.onChange = { [weak self] in self?.refresh() }
    }

    /// The place to reopen Cook Mode for a recipe: its open session, else where it was paused.
    func place(for recipeID: UUID) -> Snapshot? {
        if snapshot?.recipe.id == recipeID { return snapshot }
        if paused?.recipe.id == recipeID { return paused }
        return nil
    }

    /// Makes the next `begin` for this recipe start at the given place.
    func prepareResume(_ place: Snapshot) {
        guard snapshot?.recipe.id != place.recipe.id else { return }
        paused = place
        persist()
    }

    /// Preserve an ongoing session across launches, while clearing private photos on account changes.
    func setAccount(_ accountID: UUID?) {
        let account = accountID?.uuidString
        guard account == nil || defaults.string(forKey: accountKey) != account else { return }
        end()
        paused = nil
        persist()
        CookingActivityPhoto.clear()
        if let account { defaults.set(account, forKey: accountKey) }
        else { defaults.removeObject(forKey: accountKey) }
    }

    func begin(recipe: Recipe, servings: Int, cookedRecipeID: UUID? = nil) {
        guard !recipe.steps.isEmpty else { return }
        if snapshot?.recipe.id != recipe.id {
            end()
            if let paused, paused.recipe.id == recipe.id {
                snapshot = paused
                snapshot?.id = UUID()
            } else {
                snapshot = Snapshot(recipe: recipe, servings: servings, cookedRecipeID: cookedRecipeID)
            }
        }
        if paused?.recipe.id == recipe.id { paused = nil }
        snapshot?.servings = servings
        persist()
        activityWarning = nil
        guard defaults.bool(forKey: PreferenceKey.liveActivity) else {
            // A session restored from before the setting was turned off may still have one.
            let id = snapshot?.id, showing = activities.showing()
            enqueue { [activities] in await activities.end(showing, session: id, finished: false) }
            return
        }
        guard activities.areEnabled else {
            activityWarning = "Live Activities are off. Allow them for Calendish in the Settings app."
            return
        }
        guard let snapshot else { return }
        preparePhoto(for: snapshot)
        if activities.isShowing(session: snapshot.id) {
            refresh()
            return
        }
        do {
            let attributes = CookingActivityAttributes(sessionID: snapshot.id,
                recipeTitle: String(recipe.title.prefix(120)), stepCount: recipe.steps.count)
            try activities.start(attributes, content: content(for: snapshot))
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
        await timers.alertsScheduled()
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
        guard !timers.timers.contains(where: { $0.recipeID == snapshot.recipe.id && $0.stepIndex == index }) else {
            return .alreadyRunning
        }
        timers.start(recipe: snapshot.recipe, stepIndex: index, duration: duration)
        return .started(duration)
    }

    func refresh() {
        guard let snapshot else { return }
        let content = content(for: snapshot)
        enqueue { [activities] in await activities.update(session: snapshot.id, to: content) }
    }

    /// Ends the session. Closing with timers still running remembers the place, so the timer can lead back to it.
    func end(finished: Bool = false, keepingPlace: Bool = false) {
        photoLoad?.cancel()
        photoLoad = nil
        let previous = snapshot
        if keepingPlace, !finished, let previous,
           timers.timers.contains(where: { $0.recipeID == previous.recipe.id }) {
            paused = previous
        }
        // Only activities running now; one started later belongs to a new session.
        let showing = activities.showing()
        snapshot = nil
        persist()
        // Every way of finishing, in the app or from the Live Activity, counts toward cooked history.
        if finished, let previous, let recipeID = previous.cookedRecipeID {
            finishedCooks.add(FinishedCook(recipeID: recipeID, startedAt: previous.startedAt,
                accountID: defaults.string(forKey: accountKey).flatMap(UUID.init)))
        }
        activityWarning = nil
        // Capture the session before awaiting so a newly started activity isn't ended.
        enqueue { [activities] in await activities.end(showing, session: previous?.id, finished: finished) }
    }

    private func content(for snapshot: Snapshot) -> CookingActivities.Content {
        let timer = timers.timers
            .filter { $0.recipeID == snapshot.recipe.id && !$0.isPaused }
            .min { $0.end < $1.end }
        let step = Ingredient.convertTemperatures(in: snapshot.recipe.steps[snapshot.stepIndex], to: .current)
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
        if let snapshot { defaults.set(try? JSONEncoder().encode(snapshot), forKey: storageKey) }
        else { defaults.removeObject(forKey: storageKey) }
        if let paused { defaults.set(try? JSONEncoder().encode(paused), forKey: pausedKey) }
        else { defaults.removeObject(forKey: pausedKey) }
    }

    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = pendingUpdate
        pendingUpdate = Task {
            await previous?.value
            await action()
        }
    }
}
