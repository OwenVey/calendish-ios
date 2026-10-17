import SwiftUI

/// A controlled local-speech boundary: tests deliver what the microphone "heard", hold model
/// preparation and spoken feedback, and observe what was said. Command interpretation, the
/// cooking session, and cooking timers run unchanged, on their own storage rather than the app's.
@MainActor
private final class ControlledSpeech: HandsFreeSpeech {
    var microphoneAllowed = true
    var available = HandsFreeAvailability.ready
    var holdsFeedback = false
    private(set) var spoken: [String] = []
    private(set) var captures = 0
    private var hearing: (@MainActor (HandsFreeHearing) -> Void)?
    private var preparation: CheckedContinuation<Void, Error>?
    private var reportProgress: (@MainActor (Double) -> Void)?
    private var feedback: [CheckedContinuation<Void, Never>] = []
    var isCapturing: Bool { hearing != nil }
    var isPreparing: Bool { preparation != nil }
    var isGivingFeedback: Bool { !feedback.isEmpty }

    func requestMicrophoneAccess() async -> Bool { microphoneAllowed }
    func availability() async -> HandsFreeAvailability { available }
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        reportProgress = progress
        try await withCheckedThrowingContinuation { preparation = $0 }
    }
    func listen(_ hear: @escaping @MainActor (HandsFreeHearing) -> Void) {
        captures += 1
        hearing = hear
    }
    func stopListening() { hearing = nil }
    func speak(_ text: String) async {
        spoken.append(text)
        guard holdsFeedback else { return }
        await withCheckedContinuation { feedback.append($0) }
    }
    func stopSpeaking() { finishFeedback() }

    func hear(_ text: String, id: String = UUID().uuidString, isFinal: Bool = true) {
        hearing?(.utterance(id: id, text: text, isFinal: isFinal))
    }
    func interrupt() { hearing?(.interrupted) }
    func fail() { hearing?(.failed) }
    func reportPreparation(_ fraction: Double) { reportProgress?(fraction) }
    func finishPreparation(throwing error: Error? = nil) {
        if let error { preparation?.resume(throwing: error) } else { preparation?.resume() }
        preparation = nil
    }
    func finishFeedback() { feedback.forEach { $0.resume() }; feedback = [] }
}

@main
struct HandsFreeWorkflowApp: App {
    @State private var result = "Running hands-free cooking tests…"
    var body: some Scene {
        WindowGroup {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
        }
    }

    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    private func until(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "Timed out: \(message)", code: 1)
    }

    private let session: CookingSession = {
        let defaults = UserDefaults(suiteName: "hands-free-workflow")!
        defaults.removePersistentDomain(forName: "hands-free-workflow")
        defaults.set(false, forKey: PreferenceKey.liveActivity)
        return CookingSession(timers: CookingTimers(defaults: defaults), finishedCooks: FinishedCooks(defaults: defaults), defaults: defaults)
    }()
    /// Waits for feedback to end, as a cook would, before speaking.
    private func say(_ text: String, to handsFree: HandsFreeCooking, _ speech: ControlledSpeech, id: String = UUID().uuidString) async throws {
        try await until("feedback ends") { !handsFree.isSpeaking }
        speech.hear(text, id: id)
    }
    private var timers: CookingTimers { session.timers }

    private func recipe() -> Recipe {
        Recipe(title: "Workflow soup", summary: "", prepMinutes: 0, cookMinutes: 30, servings: 4, tags: [], symbol: "fork.knife",
               ingredients: [], steps: ["Chop the onions.", "Simmer for 5-7 minutes.", "Rest for 2 hours.", "Toast for 1 second, then serve."])
    }

    /// A fresh cooking session with no timers, and hands-free listening enabled.
    private func listening(_ given: ControlledSpeech? = nil) async throws -> (HandsFreeCooking, ControlledSpeech) {
        let speech = given ?? ControlledSpeech()
        session.end()
        timers.timers.forEach(timers.cancel)
        timers.acknowledge()
        session.begin(recipe: recipe(), servings: 4)
        let handsFree = HandsFreeCooking(speech: speech, session: session)
        handsFree.enable()
        try await until("listening") { handsFree.status == .listening && speech.isCapturing }
        return (handsFree, speech)
    }

    private func run() async throws {
        // Deliver notifications rather than AlarmKit alarms inside the harness.
        UserDefaults.standard.set(TimerAlert.notification.rawValue, forKey: PreferenceKey.timerAlert)
        try await CookingSessionWorkflowTests.run()
        let workflows: [(String, () async throws -> Void)] = [
            ("navigation", navigation),
            ("utterances", utterances),
            ("feedback", feedback),
            ("timerCommands", timerCommands),
            ("timerCompletion", timerCompletion),
            ("activation", activation),
            ("preparation", preparation),
            ("interruptions", interruptions),
        ]
        for (name, workflow) in workflows {
            do { try await workflow() }
            catch { throw NSError(domain: "\(name): \((error as NSError).domain)", code: 1) }
        }
    }

    private func navigation() async throws {
        let (handsFree, speech) = try await listening()
        try await say("Next.", to: handsFree, speech)
        try await until("next moves forward and announces the step") { session.stepIndex == 1 && speech.spoken == ["Step 2"] }
        try await say("next step", to: handsFree, speech)
        try await until("next step moves forward") { session.stepIndex == 2 && speech.spoken.last == "Step 3" }
        try await say("Go back!", to: handsFree, speech)
        try await until("go back moves backward") { session.stepIndex == 1 && speech.spoken.last == "Step 2" }
        try await say("Back", to: handsFree, speech)
        try await until("back moves backward") { session.stepIndex == 0 }
        try await say("back", to: handsFree, speech)
        try await until("back on the first step announces the boundary") { speech.spoken.last == "First step" }
        try expect(session.stepIndex == 0, "Back on the first step stays put")
        session.setStep(3)
        try await say("Next", to: handsFree, speech)
        try await until("next on the last step announces the boundary") { speech.spoken.last == "Last step" }
        try expect(session.snapshot != nil && session.stepIndex == 3, "Next on the last step never finishes cooking")
        try expect(handsFree.outcome == "Last step", "The spoken outcome is also shown")
        handsFree.stop()
    }

    private func utterances() async throws {
        let (handsFree, speech) = try await listening()
        speech.hear("Next", isFinal: false)
        try await say("What should we do next?", to: handsFree, speech)
        try await say("next time go back to the store", to: handsFree, speech)
        try await say("Start the timer when the oven beeps", to: handsFree, speech)
        try await say("mumble", to: handsFree, speech)
        // Speech is delivered in order, so a later command shows the earlier ones did nothing.
        try await say("Next", to: handsFree, speech, id: "once")
        try await until("only the final standalone command acts") { session.stepIndex == 1 && !speech.spoken.isEmpty }
        try expect(speech.spoken == ["Step 2"] && timers.timers.isEmpty, "Provisional, conversational, and unknown speech is ignored quietly")
        try await say("Next", to: handsFree, speech, id: "once")
        try await say("Next", to: handsFree, speech)
        try await until("a separate repeated command acts again") { session.stepIndex == 2 }
        try await say("back", to: handsFree, speech)
        try await until("redelivery of one utterance executes once") { session.stepIndex == 1 && speech.spoken.count == 3 }
        try expect(speech.spoken == ["Step 2", "Step 3", "Step 2"], "Each utterance gives one response")
        handsFree.stop()
    }

    private func feedback() async throws {
        let speech = ControlledSpeech()
        speech.holdsFeedback = true
        let (handsFree, _) = try await listening(speech)
        speech.hear("next")
        try await until("feedback starts") { speech.isGivingFeedback && handsFree.isSpeaking }
        speech.hear("Next")
        speech.hear("back")
        speech.finishFeedback()
        try await until("feedback ends") { !handsFree.isSpeaking }
        try await say("next", to: handsFree, speech)
        try await until("listening resumes after feedback") { session.stepIndex == 2 && speech.spoken.count == 2 }
        try expect(speech.spoken == ["Step 2", "Step 3"] && speech.captures == 1,
            "Input during the app's own feedback is ignored without restarting capture")
        speech.finishFeedback()
        try await say("back", to: handsFree, speech)
        try await until("feedback starts again") { speech.isGivingFeedback }
        handsFree.stop()
        speech.finishFeedback()
        try await Task.sleep(for: .milliseconds(50))
        try expect(handsFree.status == .off && !speech.isCapturing && speech.captures == 1,
            "Feedback ending after stopping can't resume listening")
    }

    private func timerCommands() async throws {
        let (handsFree, speech) = try await listening()
        try await say("Start timer", to: handsFree, speech)
        try await until("no duration is announced") { speech.spoken.last == "This step has no timer." }
        try expect(timers.timers.isEmpty, "A step without a duration starts no timer")
        try await say("next", to: handsFree, speech)
        try await say("start the timer", to: handsFree, speech)
        try await until("a range starts its shorter duration") { speech.spoken.last == "5-minute timer started" }
        let started = timers.timers
        try expect(started.count == 1 && started[0].stepIndex == 1 && started[0].duration == 300,
            "The voice timer matches the step's visible timer button")
        try await say("Start timer", to: handsFree, speech)
        try await until("a running timer is reported") { speech.spoken.last == "Timer already running" }
        try expect(timers.timers.map(\.id) == started.map(\.id) && timers.timers[0].end == started[0].end,
            "A running timer isn't restarted or duplicated")
        try await say("next", to: handsFree, speech)
        try await say("start timer", to: handsFree, speech)
        try await until("another step's timer starts") { speech.spoken.last == "2-hour timer started" }
        try expect(timers.timers.count == 2 && timers.timers.contains { $0.id == started[0].id },
            "Timers on earlier steps keep running after navigating")
        handsFree.stop()
    }

    private func timerCompletion() async throws {
        let (handsFree, speech) = try await listening()
        session.setStep(3)
        try await say("start timer", to: handsFree, speech)
        try await until("a short timer starts") { timers.timers.count == 1 }
        try await until("the finished timer is delivered in-app") { timers.finished.count == 1 }
        handsFree.announceFinishedTimers()
        try expect(timers.finished.isEmpty && handsFree.finishedTimers.count == 1,
            "While listening, completion shows a banner instead of the blocking alert")
        try await until("completion is announced") { speech.spoken.last == "Step 4 timer finished" }
        try expect(handsFree.isListening, "Listening continues after timer completion")
        handsFree.dismissFinishedTimers()
        try expect(handsFree.finishedTimers.isEmpty, "The banner can be dismissed")
        var other = recipe()
        other.id = UUID()
        other.title = "Other bread"
        timers.start(recipe: other, stepIndex: 0, duration: 1)
        try await until("the timer finishes") { timers.finished.count == 1 }
        handsFree.announceFinishedTimers()
        try await until("another recipe's timer is named") { speech.spoken.last == "Other bread, Step 1 timer finished" }
        try expect(handsFree.finishedTimers.map(\.recipeTitle) == ["Other bread"], "Another recipe's timer shows in the banner")
        handsFree.stop()
        try expect(handsFree.finishedTimers.isEmpty, "Turning voice commands off removes the banner")
        timers.start(recipe: session.snapshot!.recipe, stepIndex: 3, duration: 1)
        try await until("the timer finishes") { timers.finished.count == 1 }
        handsFree.announceFinishedTimers()
        try expect(timers.finished.count == 1 && handsFree.finishedTimers.isEmpty,
            "Outside hands-free use, the existing alert still delivers completion")
        timers.acknowledge()
    }

    private func activation() async throws {
        session.end()
        session.begin(recipe: recipe(), servings: 4)
        let speech = ControlledSpeech()
        let handsFree = HandsFreeCooking(speech: speech, session: session)
        try expect(handsFree.status == .off && !handsFree.keepsScreenAwake && speech.captures == 0,
            "Cook Mode never listens until voice commands are enabled")
        speech.microphoneAllowed = false
        handsFree.enable()
        try await until("denied microphone") { handsFree.status == .microphoneDenied }
        try expect(speech.captures == 0 && !handsFree.keepsScreenAwake, "Denied access never captures or overrides screen sleep")
        speech.microphoneAllowed = true
        speech.available = .unavailable("Voice commands aren’t available on this iPhone.")
        handsFree.enable()
        try await until("unavailable recognition") { handsFree.status == .unavailable("Voice commands aren’t available on this iPhone.") }
        try expect(speech.captures == 0, "Unavailable local recognition never captures")
        speech.available = .ready
        handsFree.enable()
        try await until("listening") { handsFree.isListening }
        try expect(handsFree.keepsScreenAwake, "Listening keeps the screen awake")
        handsFree.stop()
        try expect(handsFree.status == .off && !speech.isCapturing && !handsFree.keepsScreenAwake,
            "Stopping ends capture and restores the usual screen-awake preference")
        speech.hear("next")
        try expect(session.stepIndex == 0, "Speech after stopping does nothing")
    }

    private func preparation() async throws {
        session.end()
        session.begin(recipe: recipe(), servings: 4)
        let speech = ControlledSpeech()
        speech.available = .needsPreparation
        let handsFree = HandsFreeCooking(speech: speech, session: session)
        handsFree.enable()
        try await until("preparing") { speech.isPreparing && handsFree.status == .preparing(progress: 0) }
        speech.reportPreparation(0.4)
        try expect(handsFree.status == .preparing(progress: 0.4), "Preparation shows progress")
        handsFree.stop()
        speech.reportPreparation(0.8)
        speech.finishPreparation()
        try await Task.sleep(for: .milliseconds(50))
        try expect(handsFree.status == .off && speech.captures == 0, "Cancelled preparation never starts capture")

        handsFree.enable()
        try await until("preparing again") { speech.isPreparing }
        speech.finishPreparation(throwing: URLError(.notConnectedToInternet))
        try await until("preparation failure") { handsFree.status == .preparationFailed }
        try expect(speech.captures == 0, "Failed preparation doesn't capture")
        handsFree.enable()
        try await until("retrying preparation") { speech.isPreparing }
        speech.finishPreparation()
        try await until("listening after preparation") { handsFree.isListening && speech.isCapturing }

        handsFree.stop()
        handsFree.enable()
        try await until("preparing before leaving") { speech.isPreparing }
        handsFree.pause()
        speech.finishPreparation()
        try await Task.sleep(for: .milliseconds(50))
        try expect(handsFree.status == .paused && speech.captures == 1, "Preparation finishing after leaving never starts capture")
    }

    private func interruptions() async throws {
        let (handsFree, speech) = try await listening()
        try await say("next", to: handsFree, speech)
        try await until("moved") { session.stepIndex == 1 }
        try await say("start timer", to: handsFree, speech)
        try await until("timer") { timers.timers.count == 1 }
        speech.interrupt()
        try await until("interruption pauses") { handsFree.status == .paused }
        try expect(!speech.isCapturing && !handsFree.keepsScreenAwake, "An interruption stops capture visibly")
        try expect(session.stepIndex == 1 && timers.timers.count == 1, "The step and timers survive an interruption")
        try await Task.sleep(for: .milliseconds(50))
        try expect(speech.captures == 1, "Listening doesn't resume by itself")
        handsFree.enable()
        try await until("re-enabled") { handsFree.isListening && speech.captures == 2 }
        try await say("back", to: handsFree, speech)
        try await until("commands work after re-enabling") { session.stepIndex == 0 }

        handsFree.pause()
        try expect(handsFree.status == .paused && !speech.isCapturing, "Backgrounding pauses listening")
        handsFree.enable()
        try await until("re-enabled after backgrounding") { handsFree.isListening }

        speech.fail()
        try await until("failure pauses") { handsFree.status == .failed }
        try expect(!handsFree.isListening && !speech.isCapturing, "Never shows listening after capture fails")
        handsFree.enable()
        try await until("retry") { handsFree.isListening }
        try await say("next", to: handsFree, speech)
        try await until("commands work after retrying") { session.stepIndex == 1 }
        handsFree.stop()
        handsFree.pause()
        try expect(handsFree.status == .off, "Pausing after stopping stays off")
    }
}
