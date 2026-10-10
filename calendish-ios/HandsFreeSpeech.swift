import Foundation

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
