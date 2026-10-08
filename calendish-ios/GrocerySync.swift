import Foundation
import Observation

/// The internal transport seam has a Supabase adapter and a controlled test adapter.
@MainActor
protocol GrocerySyncTransport {
    func fetch(householdID: UUID) async throws -> [GroceryItem]
    func write(_ mutation: GroceryMutation, householdID: UUID) async throws
}

nonisolated struct GroceryFields: Encodable, Sendable {
    var name: String?
    var amount: String?
    var source: String?
    var isComplete: Bool?
    enum CodingKeys: String, CodingKey {
        case name, amount, source, isComplete = "is_complete"
    }
}

/// One description drives both the local overlay and the remote write.
enum GroceryMutation {
    struct Position { let id: UUID; let value: Double }
    struct Aisle { let id: UUID; let name: String; let value: String }
    case insert([GroceryItem])
    case edit(UUID, GroceryFields)
    case delete([UUID])
    case reorder([Position])
    case sort([Aisle])

    var changes: [GrocerySyncState.Change] {
        switch self {
        case .insert(let items): return items.map { .insert($0) }
        case let .edit(id, fields):
            return [.edit(id, name: fields.name, amount: fields.amount, source: fields.source,
                isComplete: fields.isComplete, position: nil)]
        case .delete(let ids): return ids.map { .delete($0) }
        case .reorder(let positions):
            return positions.map { .edit($0.id, name: nil, amount: nil, source: nil, isComplete: nil, position: $0.value) }
        case .sort(let aisles): return aisles.map { .sort($0.id, aisle: $0.value) }
        }
    }
}

/// Owns optimistic groceries and their write/read lifetime for one household.
@MainActor @Observable
final class GrocerySync {
    private(set) var items: [GroceryItem] = []
    @ObservationIgnored private let transport: (any GrocerySyncTransport)?
    @ObservationIgnored private let onChange: () -> Void
    @ObservationIgnored private let onError: (Error) -> Void
    @ObservationIgnored private let retryDelay: () async throws -> Void
    private var householdID: UUID?
    private var session = UUID()
    private var state = GrocerySyncState()
    private var writeTask: Task<Void, Never>?
    private var writes: [UUID: Task<Void, Never>] = [:]
    private var reloadTask: Task<Void, Error>?
    private var reloadID = UUID()
    private var retryReload = false

    init(transport: (any GrocerySyncTransport)?, onChange: @escaping () -> Void = {},
         onError: @escaping (Error) -> Void = { _ in },
         retryDelay: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(3)) }) {
        self.transport = transport
        self.onChange = onChange
        self.onError = onError
        self.retryDelay = retryDelay
    }

    /// Invalidate old work before publishing another household's items.
    func setHousehold(_ id: UUID?, items: [GroceryItem] = []) {
        guard householdID != id || id == nil else { return }
        session = UUID()
        cancelReload()
        for task in writes.values { task.cancel() }
        writes.removeAll()
        writeTask = nil
        state = GrocerySyncState()
        householdID = id
        self.items = items
        onChange()
    }

    func add(name: String, amount: String = "", source: String = "General") {
        insert([GroceryItem(name: name, amount: amount, source: source, position: (items.map(\.position).max() ?? 0) + 1)])
    }

    func insert(_ items: [GroceryItem]) {
        guard !items.isEmpty else { return }
        submit(.insert(items))
    }

    func toggle(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        submit(.edit(id, GroceryFields(isComplete: !item.isComplete)))
    }

    /// Text edits preserve live checkmarks, ordering, and remotely deleted items.
    func update(_ item: GroceryItem, original: GroceryItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        let fields = GroceryFields(name: original.name == item.name ? nil : item.name,
            amount: original.amount == item.amount ? nil : item.amount,
            source: original.source == item.source ? nil : item.source)
        guard fields.name != nil || fields.amount != nil || fields.source != nil else { return }
        submit(.edit(item.id, fields))
    }

    func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        submit(.delete(Array(Set(ids))))
    }

    func reorder(_ ordered: [GroceryItem]) {
        submit(.reorder(ordered.enumerated().map { .init(id: $0.element.id, value: Double($0.offset)) }))
    }

    /// Ignore classifier results for items renamed or sorted during classification.
    @discardableResult
    func assignAisles(_ aisles: [String: String]) -> [GroceryItem] {
        let assignments = items.compactMap { item -> GroceryMutation.Aisle? in
            guard item.aisle == nil, let aisle = aisles[item.name] else { return nil }
            return .init(id: item.id, name: item.name, value: aisle)
        }
        guard !assignments.isEmpty else { return [] }
        submit(.sort(assignments))
        let ids = Set(assignments.map(\.id))
        return items.filter { ids.contains($0.id) }
    }

    /// Full refresh and realtime refresh share the same single-flight fetch.
    func refresh() async throws {
        guard transport != nil, householdID != nil else { return }
        state.invalidate()
        try await startReload(retrying: false).value
    }

    func requestReload() {
        guard transport != nil, householdID != nil else { return }
        state.invalidate()
        _ = startReload(retrying: true)
    }

    func cancelReload() {
        reloadID = UUID()
        reloadTask?.cancel()
        reloadTask = nil
        retryReload = false
    }

    private func submit(_ mutation: GroceryMutation) {
        let changes = mutation.changes
        for change in changes { change.apply(to: &items) }
        items.sort { $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position }
        guard let transport, let householdID else { onChange(); return }
        let token = state.begin(changes)
        let session = session
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, session == self.session else { return }
            defer { self.writes[token] = nil }
            do { try await transport.write(mutation, householdID: householdID) }
            catch { if session == self.session, !Task.isCancelled { self.onError(error) } }
            guard !Task.isCancelled, session == self.session else { return }
            self.state.finish(token)
            self.requestReload()
        }
        writes[token] = writeTask
        onChange()
    }

    private func startReload(retrying: Bool) -> Task<Void, Error> {
        retryReload = retryReload || retrying
        if let reloadTask { return reloadTask }
        let session = session
        let id = UUID()
        reloadID = id
        let task = Task { [weak self] in
            guard let self, let transport = self.transport, let householdID = self.householdID else { return }
            defer {
                if self.reloadID == id { self.reloadTask = nil; self.retryReload = false }
            }
            var reportedFailure = false
            while !Task.isCancelled, session == self.session {
                let revision = self.state.revision
                do {
                    let serverItems = try await transport.fetch(householdID: householdID)
                    try Task.checkCancellation()
                    guard session == self.session else { return }
                    if revision != self.state.revision { continue }
                    self.items = self.state.merging(serverItems)
                    self.onChange()
                    return
                } catch {
                    guard !Task.isCancelled, session == self.session else { throw CancellationError() }
                    guard self.retryReload else { throw error }
                    if !reportedFailure { self.onError(error); reportedFailure = true }
                    try await self.retryDelay()
                }
            }
            throw CancellationError()
        }
        reloadTask = task
        return task
    }
}
