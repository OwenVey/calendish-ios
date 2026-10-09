import Foundation
import Observation

/// What hands-free cooking hears from the local speech boundary.
enum HandsFreeHearing: Sendable {
    /// Recognized speech. Only a final result is a complete utterance; its ID identifies it across redelivery.
    case utterance(id: String, text: String, isFinal: Bool)
    /// A call, Siri, or another app took the microphone.
    case interrupted
    /// Capture or recognition stopped unexpectedly, including capture ending by itself.
    case failed
}

enum HandsFreeAvailability: Equatable {
    case ready
    /// The on-device speech model must be downloaded first.
    case needsPreparation
    case unavailable(String)
}

/// The on-device microphone, recognition, and speech-feedback boundary.
@MainActor
protocol HandsFreeSpeech: AnyObject {
    func requestMicrophoneAccess() async -> Bool
    func availability() async -> HandsFreeAvailability
    /// Installs missing speech models, reporting progress from 0 to 1. Cancelled with its task.
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws
    /// Starts capture, reporting what's heard until listening stops.
    func listen(_ hear: @escaping @MainActor (HandsFreeHearing) -> Void)
    func stopListening()
    /// Speaks feedback, returning when it ends. Microphone input is ignored meanwhile.
    func speak(_ text: String) async
    func stopSpeaking()
}

/// A short, standalone spoken command. Commands embedded in longer speech don't count.
enum HandsFreeCommand: Equatable {
    case next, back, startTimer

    init?(utterance: String) {
        let words = utterance.lowercased()
            .split { !$0.isLetter && $0 != "'" }
            .joined(separator: " ")
        switch words {
        case "next", "next step": self = .next
        case "back", "go back": self = .back
        case "start timer", "start the timer": self = .startTimer
        default: return nil
        }
    }
}

/// Hands-free cook mode: listens for spoken commands while Cook Mode is visible, acting on the
/// shared cooking session and timers so voice and touch always agree on the current step.
@MainActor @Observable
final class HandsFreeCooking {
    enum Status: Equatable {
        case off
        case starting
        case preparing(progress: Double)
        case listening
        /// Stopped by backgrounding or an external audio interruption; resuming takes a tap.
        case paused
        /// Capture or recognition failed unexpectedly; retrying takes a tap.
        case failed
        case preparationFailed
        case microphoneDenied
        case unavailable(String)
    }

    private(set) var status = Status.off
    /// The latest spoken outcome, shown alongside it.
    private(set) var outcome: String?
    /// Timers that finished while listening, shown as a nonblocking banner.
    private(set) var finishedTimers: [CookTimer] = []
    private var feedbackInProgress = 0
    /// Whether spoken feedback is playing; microphone input is ignored until it ends.
    var isSpeaking: Bool { feedbackInProgress > 0 }
    var isListening: Bool { status == .listening }
    /// Hands-free use keeps the screen awake, whatever the usual preference.
    var keepsScreenAwake: Bool {
        switch status {
        case .starting, .preparing, .listening: true
        default: false
        }
    }

    @ObservationIgnored private let speech: HandsFreeSpeech
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var activation: Task<Void, Never>?
    @ObservationIgnored private var handled: Set<String> = []
    private var session: CookingSession { .shared }
    private var timers: CookingTimers { .shared }

    init(speech: HandsFreeSpeech) {
        self.speech = speech
    }

    /// Explicitly turns listening on, or retries after a pause or failure.
    func enable() {
        halt(.starting)
        let run = run
        activation = Task { await activate(run) }
    }

    /// Turns listening off. Late preparation or recognition results can't restart it.
    func stop() { halt(.off) }

    /// Stops capture when Cook Mode stops being active, keeping the step and timers.
    func pause() {
        guard keepsScreenAwake else { return }
        halt(.paused)
    }

    private func activate(_ run: Int) async {
        guard await speech.requestMicrophoneAccess() else {
            if run == self.run { status = .microphoneDenied }
            return
        }
        guard run == self.run else { return }
        switch await speech.availability() {
        case .ready: break
        case .unavailable(let reason):
            if run == self.run { status = .unavailable(reason) }
            return
        case .needsPreparation:
            guard run == self.run else { return }
            status = .preparing(progress: 0)
            do {
                try await speech.prepare { [weak self] fraction in
                    guard let self, run == self.run else { return }
                    status = .preparing(progress: fraction)
                }
            } catch {
                if run == self.run { status = .preparationFailed }
                return
            }
        }
        guard run == self.run, !Task.isCancelled else { return }
        listen(run)
    }

    private func listen(_ run: Int) {
        status = .listening
        speech.listen { [weak self] heard in
            guard let self, run == self.run else { return }
            switch heard {
            case .utterance(let id, let text, let isFinal):
                guard isFinal, feedbackInProgress == 0, handled.insert(id).inserted,
                      let command = HandsFreeCommand(utterance: text) else { return }
                perform(command, run: run)
            case .interrupted: halt(.paused)
            case .failed: halt(.failed)
            }
        }
    }

    private func perform(_ command: HandsFreeCommand, run: Int) {
        guard let snapshot = session.snapshot else { return }
        let index = snapshot.stepIndex
        switch command {
        case .next:
            if index >= snapshot.recipe.steps.count - 1 { say("Last step", run: run) }
            else {
                session.setStep(index + 1)
                say("Step \(index + 2)", run: run)
            }
        case .back:
            if index == 0 { say("First step", run: run) }
            else {
                session.setStep(index - 1)
                say("Step \(index)", run: run)
            }
        case .startTimer:
            switch session.startCurrentStepTimer() {
            case .started(let duration): say("\(Self.spoken(duration)) timer started", run: run)
            case .alreadyRunning: say("Timer already running", run: run)
            case .noDuration: say("No timer on this step", run: run)
            case nil: break
            }
        }
    }

    /// Announces timers that finished while listening, in place of the blocking alert.
    func announceFinishedTimers() {
        guard isListening, !timers.finished.isEmpty else { return }
        let finished = timers.finished
        timers.acknowledge()
        finishedTimers.append(contentsOf: finished)
        for timer in finished {
            let recipe = timer.recipeID == session.snapshot?.recipe.id ? "" : "\(timer.recipeTitle), "
            say("\(recipe)Step \(timer.stepIndex + 1) timer done", run: run)
        }
    }

    func dismissFinishedTimers() { finishedTimers.removeAll() }

    private func say(_ text: String, run: Int) {
        outcome = text
        feedbackInProgress += 1
        Task {
            await speech.speak(text)
            if run == self.run { feedbackInProgress -= 1 }
        }
    }

    private func halt(_ next: Status) {
        run += 1
        activation?.cancel()
        activation = nil
        speech.stopSpeaking()
        speech.stopListening()
        feedbackInProgress = 0
        // Utterance IDs only identify speech within one capture.
        handled.removeAll()
        outcome = nil
        finishedTimers.removeAll()
        status = next
    }

    /// "5-minute", or "1 hour, 30 minutes" when a duration has several parts.
    static func spoken(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let parts = [(seconds / 3600, "hour"), (seconds % 3600 / 60, "minute"), (seconds % 60, "second")].filter { $0.0 > 0 }
        if parts.count == 1, let (value, unit) = parts.first { return "\(value)-\(unit)" }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
