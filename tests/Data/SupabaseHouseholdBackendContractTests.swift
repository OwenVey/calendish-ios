import Foundation
import Supabase

/// Small wire-contract checks complement the in-memory store workflows; they do not simulate SQL rules.
private actor HouseholdWireRequests {
    static let shared = HouseholdWireRequests()
    var requests: [URLRequest] = []
    /// The JSON every request receives.
    var response = Data("[]".utf8)
    func record(_ request: URLRequest) -> Data { requests.append(request); return response }
    func respond(with json: String) { response = Data(json.utf8) }
    func last() -> URLRequest { requests.last! }
}
private final nonisolated class HouseholdWireProtocol: URLProtocol, @unchecked Sendable {
    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override nonisolated func startLoading() {
        Task {
            let body = await HouseholdWireRequests.shared.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override nonisolated func stopLoading() { }
}
private final class HouseholdWireAuthStorage: AuthLocalStorage, @unchecked Sendable {
    func store(key: String, value: Data) { }
    func retrieve(key: String) -> Data? { nil }
    func remove(key: String) { }
}
@MainActor
enum SupabaseHouseholdBackendContractTests {
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HouseholdWireProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:1")!, supabaseKey: "wire-test",
            options: .init(auth: .init(storage: HouseholdWireAuthStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration))))
        let backend = SupabaseHouseholdBackend(client: client)
        var recipe = SampleRecipes.all[0]
        let person = UUID(), household = UUID()
        recipe.owner = .person(person, shared: true)
        let meal = PlannedMeal(date: .now, recipe: recipe, recipeID: recipe.id, servings: 3)
        try await backend.write(.saveMeal(meal, household: household, keepVersion: true))
        let kept = await HouseholdWireRequests.shared.last()
        let keptBody = try body(kept)
        try expect(kept.url?.path == "/rest/v1/rpc/save_planned_meal" && keptBody["meal_recipe"] is NSNull
            && keptBody["keep_version"] as? Bool == true && keptBody["meal_servings"] as? Int == 3,
            "Keeping a meal version sends the required explicit null recipe argument")
        try await backend.write(.saveMeal(meal, household: household, keepVersion: false))
        let captured = await HouseholdWireRequests.shared.last()
        try expect(try (body(captured)["meal_recipe"] as? String)?.lowercased() == recipe.id.uuidString.lowercased(), "Capturing a meal sends its source recipe ID")
        try await backend.write(.saveRecipe(recipe, isNew: false, upload: nil, stalePhoto: nil))
        let edited = await HouseholdWireRequests.shared.last()
        let editedBody = try body(edited)
        try expect(edited.httpMethod == "PATCH" && editedBody["owner_id"] == nil && editedBody["household_id"] == nil
            && editedBody["is_shared"] == nil, "Recipe edits omit ownership and sharing fields")
        try await backend.write(.saveRecipe(recipe, isNew: true, upload: nil, stalePhoto: nil))
        let inserted = await HouseholdWireRequests.shared.last()
        let insertedBody = try body(inserted)
        try expect(inserted.httpMethod == "POST" && (insertedBody["owner_id"] as? String)?.lowercased() == person.uuidString.lowercased()
            && insertedBody["is_shared"] as? Bool == true, "New recipes carry their personal owner")
        try await backend.write(.markCooked(household: household, recipe: recipe.id, day: meal.date))
        let cooked = await HouseholdWireRequests.shared.last()
        try expect(cooked.url?.path == "/rest/v1/recipe_cooks"
            && cooked.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") == true,
            "Marking cooked keeps duplicate-safe upsert semantics")
        let snapshot = try await backend.snapshot(household: household)
        try expect(snapshot.household == nil && snapshot.recipes.isEmpty, "An RLS-hidden household remains absent")

        await HouseholdWireRequests.shared.respond(with: #""occupied""#)
        let outcome = try await backend.addMeal(meal, household: household, expectedRevision: 4)
        let added = await HouseholdWireRequests.shared.last()
        let addedBody = try body(added)
        try expect(added.url?.path == "/rest/v1/rpc/add_planned_meal"
            && (addedBody["target_household"] as? String)?.lowercased() == household.uuidString.lowercased()
            && (addedBody["meal_id"] as? String)?.lowercased() == meal.id.uuidString.lowercased()
            && addedBody["meal_date"] as? String == DayFormat.string(from: meal.date)
            && (addedBody["meal_recipe"] as? String)?.lowercased() == recipe.id.uuidString.lowercased()
            && addedBody["expected_revision"] as? Int == 4 && addedBody["meal_servings"] as? Int == 3,
            "A guarded add sends the meal identity, day, recipe, reviewed revision, and servings")
        try expect(outcome == .occupied, "A guarded add reports the server's outcome")
        await HouseholdWireRequests.shared.respond(with: #""already_added""#)
        let repeated = try await backend.addMeal(meal, household: household, expectedRevision: 4)
        try expect(repeated == .alreadyAdded, "A repeated add is recognized as an earlier success")
        await HouseholdWireRequests.shared.respond(with: "[]")

        let row = try JSONDecoder().decode(RecipeRecord.self, from: Data("""
            {"id":"\(recipe.id.uuidString)","title":"Soup","summary":"","minutes":5,"servings":2,"tags":[],"symbol":"fork.knife",
             "ingredients":[],"steps":[],"household_id":"\(household.uuidString)","revision":3}
            """.utf8))
        let current = Recipe(row)
        var saved = row
        saved.revision = nil; saved.householdID = nil
        try expect(current.revision == 3 && PlannedMeal(date: .now, recipe: current, recipeID: current.id, servings: 2).recipe.revision == nil
            && current.hasSameVersion(as: Recipe(saved)), "Revisions decode from recipes without affecting saved-version comparisons")
    }
}
