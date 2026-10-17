import Foundation
import Observation

/// Owns the household's grocery list, including sync, checked-item expiry, and aisle sorting.
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
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autoClearInterval: () -> TimeInterval?
    @ObservationIgnored private let classifyAisles: (([String]) async -> [String: String])?
    private var checkedAt: [String: Date]
    private static let checkedAtKey = "groceryCheckedAt"
    private var aisleTask: Task<Void, Never>?
    private var sortedNames: [UUID: String] = [:]

    init(transport: (any GrocerySyncTransport)?, onChange: @escaping () -> Void = { },
         onError: @escaping (Error) -> Void = { _ in },
         retryDelay: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(3)) },
         defaults: UserDefaults? = nil, now: @escaping () -> Date = { .now },
         autoClearInterval: @escaping () -> TimeInterval? = { nil },
         classifyAisles: (([String]) async -> [String: String])? = nil) {
        self.transport = transport
        self.onChange = onChange
        self.onError = onError
        self.retryDelay = retryDelay
        self.defaults = defaults
        self.now = now
        self.autoClearInterval = autoClearInterval
        self.classifyAisles = classifyAisles
        checkedAt = defaults?.dictionary(forKey: Self.checkedAtKey) as? [String: Date] ?? [:]
    }

    /// Invalidate old work before publishing another household's items.
    func setHousehold(_ id: UUID?, items: [GroceryItem] = []) {
        guard householdID != id || id == nil else { return }
        session = UUID()
        aisleTask?.cancel(); aisleTask = nil
        sortedNames = [:]
        cancelReload()
        for task in writes.values { task.cancel() }
        writes.removeAll()
        writeTask = nil
        state = GrocerySyncState()
        householdID = id
        self.items = items
        itemsChanged()
    }

    var remainingCount: Int { items.filter { !$0.isComplete }.count }

    func clearCompleted() { remove(items.filter(\.isComplete).map(\.id)) }

    func clearAll() { remove(items.map(\.id)) }

    func applyImport(_ changes: GroceryImport) {
        guard householdID != nil else { return }
        for (item, original) in changes.updated { update(item, original: original) }
        insert(changes.added)
    }

    /// The clock starts when this device first observes a checkmark, including remote checkmarks.
    func clearExpired() {
        guard let interval = autoClearInterval() else { return }
        let cutoff = now().addingTimeInterval(-interval)
        remove(items.filter { $0.isComplete && checkedAt[$0.id.uuidString].map { $0 <= cutoff } == true }.map(\.id))
    }

    private func itemsChanged() {
        let date = now()
        let checks = Dictionary(items.map { ($0.id.uuidString, $0.isComplete) }, uniquingKeysWith: { first, _ in first })
        // Missing items may not have loaded yet. Retain their stamps for up to a month.
        var stamps = checkedAt.filter { id, stamp in checks[id] ?? (date.timeIntervalSince(stamp) < 30 * 86400) }
        for (id, checked) in checks where checked && stamps[id] == nil { stamps[id] = date }
        if stamps != checkedAt {
            checkedAt = stamps
            defaults?.set(stamps, forKey: Self.checkedAtKey)
        }
        clearExpired()
        sortIntoAisles()
        onChange()
    }

    private func sortIntoAisles() {
        guard aisleTask == nil, householdID != nil, let classifyAisles else { return }
        let session = session
        aisleTask = Task { [weak self] in
            guard let self else { return }
            defer { if session == self.session { self.aisleTask = nil } }
            while !Task.isCancelled, session == self.session {
                let unsorted = items.filter { $0.aisle == nil && self.sortedNames[$0.id] != $0.name }
                guard !unsorted.isEmpty else { return }
                let aisles = await classifyAisles(Array(Set(unsorted.map(\.name))))
                guard !Task.isCancelled, session == self.session else { return }
                // Remember attempted names even if classification omitted one or its save fails.
                // New or renamed items are picked up by the next batch.
                for item in unsorted { sortedNames[item.id] = item.name }
                assignAisles(aisles)
            }
        }
    }

    func add(name: String) { add(names: [name]) }

    /// Adds ordinary groceries after everything on the list, in the given order.
    /// Names are trimmed and blank ones skipped; a repeated name gets its own row.
    @discardableResult
    func add(names: [String]) -> [GroceryItem] {
        let added = GroceryItem.general(named: names, after: items)
        insert(added)
        return added
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
        guard let transport, let householdID else { itemsChanged(); return }
        let token = state.begin(changes)
        let session = session
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, session == self.session else { return }
            defer { self.writes[token] = nil }
            do { try await transport.write(mutation, householdID: householdID) }
            catch { if session == self.session, !Task.isCancelled { onError(error) } }
            guard !Task.isCancelled, session == self.session else { return }
            state.finish(token)
            requestReload()
        }
        writes[token] = writeTask
        itemsChanged()
    }

    private func startReload(retrying: Bool) -> Task<Void, Error> {
        retryReload = retryReload || retrying
        if let reloadTask { return reloadTask }
        let session = session
        let id = UUID()
        reloadID = id
        let task = Task { [weak self] in
            guard let self, let transport, let householdID else { return }
            defer {
                if self.reloadID == id { self.reloadTask = nil; self.retryReload = false }
            }
            var reportedFailure = false
            while !Task.isCancelled, session == self.session {
                let revision = state.revision
                do {
                    let serverItems = try await transport.fetch(householdID: householdID)
                    try Task.checkCancellation()
                    guard session == self.session else { return }
                    if revision != state.revision { continue }
                    items = state.merging(serverItems)
                    itemsChanged()
                    return
                } catch {
                    guard !Task.isCancelled, session == self.session else { throw CancellationError() }
                    guard retryReload else { throw error }
                    if !reportedFailure { onError(error); reportedFailure = true }
                    try await retryDelay()
                }
            }
            throw CancellationError()
        }
        reloadTask = task
        return task
    }
}
