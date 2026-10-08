import SwiftUI
import Supabase

/// The store's client seam uses a controlled HTTP boundary, while the production models,
/// encoding, auth event stream, and household lifetime guards run unchanged.
private final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}

private actor FixtureServer {
    static let shared = FixtureServer()
    let person = UUID()
    let home = UUID()
    let destination = UUID()
    var current: UUID?
    var recipes: [[String: Any]] = []
    var meals: [[String: Any]] = []
    var holdRecipeRead = false
    var holdCopy = false
    var loseJoinResponse = false
    var held: CheckedContinuation<Void, Never>?
    var hasHeldRequest: Bool { held != nil }

    func release() { held?.resume(); held = nil }
    func delayNextRead() { holdRecipeRead = true }
    func delayCopy() { holdCopy = true }
    func loseNextJoinResponse() { loseJoinResponse = true }

    func household(_ id: UUID) -> [String: Any] {
        ["id": id.uuidString, "name": id == home ? "Original household" : "Partner household", "invite_code": "VALID123"]
    }
    func recipe(_ title: String, owner: UUID? = nil) -> [String: Any] {
        ["id": UUID().uuidString, "owner_id": (owner ?? person).uuidString, "is_shared": true,
         "title": title, "summary": "", "minutes": 10, "prep_minutes": 0, "cook_minutes": 10,
         "servings": 4, "tags": [], "symbol": "fork.knife", "ingredients": [["id": UUID().uuidString, "text": "1 cup rice"]], "steps": ["Cook rice."]]
    }
    func preview() -> [String: Any] {
        ["destination": household(destination).merging(["members": ["Partner"]]) { _, new in new },
         "current_household_id": current?.uuidString as Any, "current_household_name": "Original household",
         "is_current": false, "other_members": 0, "successor": NSNull(), "deletes_household": true,
         "personal_recipes": recipes.count, "shared_recipes": recipes.count, "household_recipes": 0, "planned_meals": meals.count, "groceries": 0]
    }
    func respond(_ request: URLRequest) async throws -> (Int, Data) {
        let path = request.url!.path
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                collected.append(contentsOf: bytes.prefix(count))
            }
            body = collected
        }
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        var value: Any = []
        var status = 200
        switch path {
        case "/auth/v1/token":
            value = ["access_token": "fixture-token", "refresh_token": "fixture-refresh", "token_type": "bearer", "expires_in": 3600, "expires_at": Int(Date.now.timeIntervalSince1970) + 3600,
                     "user": ["id": person.uuidString, "aud": "authenticated", "role": "authenticated", "email": "fixture@example.com", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z", "app_metadata": [:], "user_metadata": [:]]]
        case "/auth/v1/logout": return (204, Data())
        case "/rest/v1/household_members":
            value = current.map { [["household_id": $0.uuidString, "user_id": person.uuidString, "display_name": "Fixture", "role": "owner", "joined_at": "2026-01-01T00:00:00Z"]] } ?? []
        case "/rest/v1/households": value = current.map { [household($0)] } ?? []
        case "/rest/v1/recipes":
            if request.httpMethod == "PATCH", let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
               let id = query.first(where: { $0.name == "id" })?.value?.replacingOccurrences(of: "eq.", with: ""),
               let index = recipes.firstIndex(where: { $0["id"] as? String == id }) {
                recipes[index].merge(input) { _, new in new }
            } else if request.httpMethod == "POST" { recipes.append(input) }
            value = recipes
            if holdRecipeRead && request.httpMethod == "GET" {
                holdRecipeRead = false
                let captured = try JSONSerialization.data(withJSONObject: value)
                await withCheckedContinuation { held = $0 }
                return (200, captured)
            }
        case "/rest/v1/planned_meals": value = meals
        case "/rest/v1/rpc/start_household":
            current = current ?? (input["code"] == nil ? home : destination)
            if recipes.isEmpty { recipes = [recipe("Original recipe")] }
            value = household(current!)
        case "/rest/v1/rpc/preview_household_move": value = preview()
        case "/rest/v1/rpc/join_household":
            if input["code"] as? String != "VALID123" {
                status = 404; value = ["code": "P0002", "message": "Invitation revoked"]
            } else {
                current = destination
                recipes = [recipe("Destination recipe")]
                meals = []
                if loseJoinResponse { loseJoinResponse = false; throw URLError(.networkConnectionLost) }
                value = ["household": household(destination), "unused_photos": []]
            }
        case "/rest/v1/rpc/save_recipe_copy":
            var copy = recipe("Private copy"); copy["is_shared"] = false
            value = copy
            if holdCopy { holdCopy = false; await withCheckedContinuation { held = $0 } }
        case "/rest/v1/rpc/save_planned_meal":
            guard input.keys.contains("meal_recipe") else {
                return (400, try JSONSerialization.data(withJSONObject: ["code": "PGRST202", "message": "Missing required meal_recipe parameter"]))
            }
            let source: [String: Any]
            if input["keep_version"] as? Bool == true {
                source = meals.first!["recipe"] as! [String: Any]
            } else {
                source = recipes.first { $0["id"] as? String == input["meal_recipe"] as? String }!
            }
            meals = [["id": input["meal_id"]!, "household_id": current!.uuidString, "date": input["meal_date"]!, "slot": input["meal_slot"]!, "recipe_id": source["id"]!, "servings": input["meal_servings"]!, "recipe": source]]
        default: value = []
        }
        if request.value(forHTTPHeaderField: "Accept")?.contains("vnd.pgrst.object") == true,
           let rows = value as? [[String: Any]], let first = rows.first { value = first }
        return (status, try JSONSerialization.data(withJSONObject: value))
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func startLoading() {
        Task {
            do {
                let (status, data) = try await FixtureServer.shared.respond(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    nonisolated override func stopLoading() { }
}

@main
struct HouseholdWorkflowApp: App {
    @State private var result = "Running workflow tests…"
    @State private var uiStore = HouseholdStore.preview()
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ui-setup") {
                HouseholdSetupView().environment(uiStore)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-leave") {
                HouseholdMoveView(leaving: true).environment(uiStore)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-invite") {
                ContentView(store: uiStore).onAppear {
                    if ProcessInfo.processInfo.arguments.contains("--ui-invite") {
                        _ = uiStore.openInvite(URL(string: "calendish://join/VALID123")!)
                    }
                }
            } else {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
            }
        }
    }
    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    private func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "Timed out waiting for workflow state", code: 1)
    }
    private func run() async throws {
        UserDefaults.standard.removeObject(forKey: "pendingHouseholdInvite")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:1")!, supabaseKey: "fixture",
            options: .init(auth: .init(storage: MemoryAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                           global: .init(session: URLSession(configuration: configuration))))
        let store = HouseholdStore(client: client)
        let session = Task { await store.start() }
        defer { session.cancel() }
        try await until { store.phase == .signedOut }
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .onboarding }
        await FixtureServer.shared.delayNextRead()
        let entering = Task { try await store.startHousehold(memberName: "Fixture") }
        try await until { await FixtureServer.shared.hasHeldRequest }
        await store.signOut()
        try await until { store.phase == .signedOut }
        await FixtureServer.shared.release()
        do { try await entering.value; throw NSError(domain: "Stale entry must cancel", code: 1) }
        catch is CancellationError { }
        try expect(store.phase == .signedOut && store.household == nil,
            "Sign-out during onboarding reload cannot resurrect ready state")
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .ready }
        try expect(store.phase == .ready && store.recipes.first?.title == "Original recipe", "Solo onboarding loads the household and recipes")
        let originalHome = store.household!.id
        let original = store.recipes[0]
        store.saveMeal(date: .now, slot: .dinner, recipe: original, servings: 6)
        try await until { store.meals.first?.servings == 6 }
        // Wait for the queued write's authoritative reload before editing the original.
        try await Task.sleep(for: .milliseconds(100))
        var edited = original; edited.steps = ["Different instructions."]
        store.saveRecipe(edited)
        try await until { store.recipes.first?.steps == ["Different instructions."] }
        try await Task.sleep(for: .milliseconds(100))
        try expect(store.meals.first?.recipe.steps == ["Cook rice."] && store.meals.first?.servings == 6, "Recipe edits leave saved meal content and servings unchanged")
        let savedMeal = store.meals[0]
        store.saveMeal(date: savedMeal.date, slot: .lunch, recipe: savedMeal.recipe, servings: 3, moving: savedMeal, keepVersion: true)
        try await Task.sleep(for: .milliseconds(200))
        await store.refresh()
        try expect(store.meals.first?.slot == .lunch && store.meals.first?.recipe.steps == ["Cook rice."],
            "Moving a meal persists its saved version through the Swift RPC encoding")
        let preview = try await store.previewMove(code: "VALID123")
        do {
            try await store.joinHousehold(code: "INVALID", confirmed: preview, saveHouseholdRecipes: false)
            throw NSError(domain: "Invalid invitation unexpectedly succeeded", code: 1)
        } catch let error as PostgrestError { try expect(error.code == "P0002", "Invalid invitation returns a useful error") }
        try expect(store.household?.id == originalHome && !store.meals.isEmpty, "Rejected move keeps membership and meals")
        await FixtureServer.shared.delayNextRead()
        let oldRead = Task { await store.refresh() }
        try await until { await FixtureServer.shared.hasHeldRequest }
        await FixtureServer.shared.loseNextJoinResponse()
        try await store.joinHousehold(code: "VALID123", confirmed: preview, saveHouseholdRecipes: false)
        try expect(store.household?.id != originalHome && store.recipes.first?.title == "Destination recipe", "Lost move response recovers from authoritative membership")
        await FixtureServer.shared.release()
        await oldRead.value
        try expect(store.recipes.first?.title == "Destination recipe" && store.meals.isEmpty, "Late former-household reload cannot republish old content")
        await FixtureServer.shared.delayCopy()
        let copy = Task { try await store.saveCopy(of: store.recipes[0]) }
        try await until { await FixtureServer.shared.hasHeldRequest }
        await store.signOut()
        try await until { store.phase == .signedOut }
        await FixtureServer.shared.release()
        do { _ = try await copy.value; throw NSError(domain: "Stale copy must cancel", code: 1) }
        catch is CancellationError { }
        try expect(store.recipes.isEmpty && store.household == nil, "Late copy cannot repopulate a signed-out account")
        try expect(store.openInvite(URL(string: "calendish://join/VALID123")!), "Join links are recognized while signed out")
        let reopened = HouseholdStore(client: client)
        try expect(reopened.pendingInvite == "VALID123", "Invitations survive a new store instance before authentication")
        let reopenedSession = Task { await reopened.start() }
        defer { reopenedSession.cancel() }
        try await until { reopened.phase == .signedOut }
        try await reopened.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { reopened.phase == .ready }
        try expect(reopened.inviteToReview?.code == "VALID123" && reopened.pendingInvite == nil,
            "Authentication continues the pending invitation as a review without moving membership")
        UserDefaults.standard.removeObject(forKey: "pendingHouseholdInvite")

    }
}
