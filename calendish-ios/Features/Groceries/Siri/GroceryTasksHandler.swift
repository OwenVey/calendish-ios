import Intents

/// Handles "Add apples to Calendish" through SiriKit's lists domain, which accepts any spoken item in one sentence.
/// iOS 27 replaces this with `CreateGroceryReminderIntent`; see docs/adr/0005-spoken-grocery-add.md.
final class GroceryTasksHandler: NSObject, INAddTasksIntentHandling {
    /// The household has one grocery list, so every request lands there whatever list Siri heard.
    private static let list = INSpeakableString(spokenPhrase: "Groceries")

    func resolveTaskTitles(for intent: INAddTasksIntent) async -> [INSpeakableStringResolutionResult] {
        let titles = intent.taskTitles ?? []
        guard !titles.isEmpty else { return [.needsValue()] }
        return titles.map { .success(with: $0) }
    }

    func resolveTargetTaskList(for intent: INAddTasksIntent) async -> INTaskListResolutionResult {
        .success(with: Self.taskList(tasks: []))
    }

    func handle(intent: INAddTasksIntent) async -> INAddTasksIntentResponse {
        // Siri splits on "and", which would turn "mac and cheese" into two groceries. One request adds one grocery.
        let item = (intent.taskTitles ?? []).map(\.spokenPhrase).formatted(.list(type: .and))
        guard let adder = await SpokenGroceryAdd.live() else { return .init(code: .failureRequiringAppLaunch, userActivity: nil) }
        do {
            let outcomes = try await adder.add([item])
            // SiriKit can't say "already on your list", so an item already there is reported as added:
            // either way it's now on the list.
            let tasks = outcomes.map(\.name).map { INTask(title: INSpeakableString(spokenPhrase: $0), status: .notCompleted, taskType: .completable,
                                           spatialEventTrigger: nil, temporalEventTrigger: nil, createdDateComponents: nil,
                                           modifiedDateComponents: nil, identifier: nil) }
            let response = INAddTasksIntentResponse(code: .success, userActivity: nil)
            response.modifiedTaskList = Self.taskList(tasks: tasks)
            response.addedTasks = tasks
            return response
        } catch SpokenGroceryAdd.Failure.noHousehold {
            return .init(code: .failureRequiringAppLaunch, userActivity: nil)
        } catch {
            return .init(code: .failure, userActivity: nil)
        }
    }

    private static func taskList(tasks: [INTask]) -> INTaskList {
        INTaskList(title: list, tasks: tasks, groupName: nil, createdDateComponents: nil, modifiedDateComponents: nil, identifier: "groceries")
    }
}
