import Foundation

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
