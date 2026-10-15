import Foundation

nonisolated struct PushDeviceRegistration: Encodable {
    let installation: UUID
    let device_token: String
    let push_environment: String
    let recipes_enabled: Bool
}
