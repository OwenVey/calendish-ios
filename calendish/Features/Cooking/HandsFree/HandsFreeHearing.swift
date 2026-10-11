import Foundation

/// What hands-free cooking hears from the local speech boundary.
enum HandsFreeHearing: Sendable {
    /// Recognized speech. Only a final result is a complete utterance; its ID identifies it across redelivery.
    case utterance(id: String, text: String, isFinal: Bool)
    /// A call, Siri, or another app took the microphone.
    case interrupted
    /// Capture or recognition stopped unexpectedly, including capture ending by itself.
    case failed
}
