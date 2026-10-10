import Foundation

/// Finished cooks waiting for the household to record them. They're kept on the device because the Live Activity
/// can finish a cook while the app runs in the background, before the household has loaded.
final class FinishedCooks {
    static let shared = FinishedCooks()
    private let defaults: UserDefaults
    private let storageKey = "finishedCooks"
    private var recorder: (accountID: UUID, record: (FinishedCook, @escaping (Bool) -> Void) -> Void)?
    private var recordingSession = UUID()
    private var activeDelivery: UUID?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Cooks not yet acknowledged by household persistence, oldest first.
    var pending: [FinishedCook] {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([FinishedCook].self, from: $0) } ?? []
    }

    func add(_ cook: FinishedCook) {
        if !pending.contains(cook) { save(pending + [cook]) }
        drain()
    }

    /// Delivers waiting cooks one at a time. Acknowledge only after persistence succeeds or the recipe is unavailable.
    /// A failed acknowledgment keeps the cook pending until retry or the next recording session.
    /// Cooks finished under another account are dropped rather than recorded for the wrong household.
    func record(for accountID: UUID, with record: @escaping (FinishedCook, @escaping (Bool) -> Void) -> Void) {
        stopRecording()
        recorder = (accountID, record)
        drain()
    }

    /// Keeps finished cooks waiting until a household loads again. Late acknowledgments cannot drain a new session.
    func stopRecording() {
        recorder = nil
        recordingSession = UUID()
        activeDelivery = nil
    }

    /// Retries retained cooks after a failed write, such as when the app resumes.
    func retry() { drain() }

    private func drain() {
        guard let recorder, activeDelivery == nil else { return }
        // Keep the existing rule: cooks from another account are discarded, never reassigned.
        let cooks = pending.filter { $0.accountID == recorder.accountID }
        save(cooks)
        guard let cook = cooks.first else { return }
        let session = recordingSession
        let delivery = UUID()
        activeDelivery = delivery
        recorder.record(cook) { [weak self] acknowledged in
            guard let self, session == self.recordingSession, self.activeDelivery == delivery else { return }
            self.activeDelivery = nil
            guard acknowledged else { return }
            self.save(self.pending.filter { $0 != cook })
            self.drain()
        }
    }

    private func save(_ cooks: [FinishedCook]) {
        if cooks.isEmpty { defaults.removeObject(forKey: storageKey) }
        else { defaults.set(try? JSONEncoder().encode(cooks), forKey: storageKey) }
    }
}
