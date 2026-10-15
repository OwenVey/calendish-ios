import Foundation
import Supabase

/// APNs tokens stay behind authenticated RPCs; clients cannot read another person's devices.
@MainActor
struct HouseholdPushTransport {
    let client: SupabaseClient

    func register(installation: UUID, token: String, enabled: Bool) async throws {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try await client.rpc("register_push_device", params: PushDeviceRegistration(
            installation: installation, device_token: token, push_environment: environment, recipes_enabled: enabled)).execute()
    }

    func unregister(installation: UUID) async throws {
        try await client.rpc("unregister_push_device", params: ["installation": installation.uuidString.lowercased()]).execute()
    }
}
