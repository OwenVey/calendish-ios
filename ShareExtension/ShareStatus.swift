import Foundation

@Observable
final class ShareStatus {
    enum State { case saving, saved, unsupported, failed }
    var state = State.saving
}
