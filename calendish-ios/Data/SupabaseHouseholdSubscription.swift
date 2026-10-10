import SwiftUI
import Supabase
import GoogleSignIn
import CryptoKit

@MainActor
final class SupabaseHouseholdSubscription: HouseholdSubscription {
    let changes: AsyncStream<HouseholdChange>
    private let continuation: AsyncStream<HouseholdChange>.Continuation
    private let client: SupabaseClient
    private let householdChannel: RealtimeChannelV2
    private let personalChannel: RealtimeChannelV2
    private var tasks: [Task<Void, Never>] = []
    private var cancelled = false
    var isConnected: Bool { !cancelled && householdChannel.status == .subscribed && personalChannel.status == .subscribed }
    init(client: SupabaseClient, household: UUID, user: UUID) {
        self.client = client
        (changes, continuation) = AsyncStream.makeStream()
        householdChannel = client.channel("household:\(household.uuidString.lowercased())") { $0.isPrivate = true }
        personalChannel = client.channel("user:\(user.uuidString.lowercased())") { $0.isPrivate = true }
    }
    func start() async {
        await client.realtimeV2.setAuth()
        guard !cancelled else { return }
        for channel in [householdChannel, personalChannel] {
            let personal = channel === personalChannel
            let broadcasts = channel.broadcastStream(event: "CHANGE")
            let statuses = channel.statusChange
            tasks.append(Task { [weak self] in
                for await payload in broadcasts {
                    guard !Task.isCancelled, let self else { return }
                    // SDK broadcasts wrap the RLS-authorized table hint inside payload.
                    guard let table = payload["payload"]?.objectValue?["table"]?.stringValue else { continue }
                    self.continuation.yield(table == "grocery_items" ? .groceries : table == "household_members" && personal ? .membership : .household)
                }
            })
            tasks.append(Task { [weak self] in
                for await status in statuses {
                    guard !Task.isCancelled else { return }
                    // Fetch on every successful join, closing load gaps and recovering missed events.
                    if status == .subscribed { self?.continuation.yield(personal ? .membership : .household) }
                }
            })
        }
        tasks.append(Task { [weak self] in
            var reportedFailure = false
            while !Task.isCancelled {
                guard let self else { return }
                for channel in [self.householdChannel, self.personalChannel] where channel.status != .subscribed {
                    do { try await channel.subscribeWithError(); reportedFailure = false }
                    catch {
                        guard !Task.isCancelled else { return }
                        if !reportedFailure { self.continuation.yield(.failure(error)); reportedFailure = true }
                    }
                }
                // Retry beyond the SDK's finite reconnect budget while the app remains open.
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        })
    }
    func cancel() async {
        cancelled = true
        for task in tasks { task.cancel() }
        tasks = []
        continuation.finish()
        await client.removeChannel(householdChannel)
        await client.removeChannel(personalChannel)
    }
}
