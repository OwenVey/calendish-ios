import Foundation

@MainActor
protocol HouseholdBackend: AnyObject, Sendable {
    var account: HouseholdAccount? { get }
    var authChanges: AsyncStream<HouseholdAuthChange> { get }
    var groceryTransport: (any GrocerySyncTransport)? { get }
    var aisleClassifier: (([String]) async -> [String: String])? { get }
    func authenticate(_ credentials: HouseholdCredentials) async throws -> Bool
    func signOut() async throws
    func currentHousehold(user: UUID) async throws -> HouseholdRecord?
    func startHousehold(name: String, code: String?) async throws -> HouseholdRecord
    func snapshot(household: UUID) async throws -> HouseholdSnapshot
    func subscribe(household: UUID, user: UUID) async -> any HouseholdSubscription
    func write(_ mutation: HouseholdMutation) async throws
    func previewMove(code: String?) async throws -> HouseholdMovePreview
    func move(code: String?, saveRecipes: Bool, expected: UUID?) async throws -> HouseholdMoveResult
    func copyRecipe(_ id: UUID) async throws -> Recipe
    func deleteHouseholdData(_ id: UUID) async throws -> [String]
    func deleteAccount(_ user: UUID) async throws
    func uploadPhoto(_ upload: HouseholdPhotoUpload, bucket: HouseholdPhotoBucket) async throws
    func removePhotos(_ paths: [String], bucket: HouseholdPhotoBucket) async
    func avatar(household: UUID, user: UUID) async throws -> URL?
}
