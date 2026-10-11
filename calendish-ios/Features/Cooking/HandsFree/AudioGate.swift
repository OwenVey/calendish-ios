import Foundation

/// Whether captured audio is replaced with silence, read from the audio thread.
final nonisolated class AudioGate: @unchecked Sendable {
    private let lock = NSLock()
    private var muted = false
    var isMuted: Bool {
        get { lock.withLock { muted } }
        set { lock.withLock { muted = newValue } }
    }
}
