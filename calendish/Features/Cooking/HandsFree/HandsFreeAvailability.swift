import Foundation

enum HandsFreeAvailability: Equatable {
    case ready
    /// The on-device speech model must be downloaded first.
    case needsPreparation
    case unavailable(String)
}
