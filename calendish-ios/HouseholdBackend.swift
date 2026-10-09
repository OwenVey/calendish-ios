import Foundation

/// App values cross this seam; SDK sessions, query builders, and channels stay in the adapter.
struct HouseholdAccount {
    var id: UUID
    var email: String?
    var displayName = ""
    var avatarURL: URL?
}
struct HouseholdAuthChange {
    var account: HouseholdAccount?
    var passwordRecovery = false
}
struct HouseholdSnapshot {
    var household: Household?
    var members: [HouseholdMember] = []
    var recipes: [Recipe] = []
    var meals: [PlannedMeal] = []
    var notes: [MealPlanNote] = []
    var reviews: [RecipeReview] = []
    var cooks: [RecipeCook] = []
}
enum HouseholdChange {
    case household, membership, groceries, failure(Error)
}
@MainActor
protocol HouseholdSubscription: AnyObject {
    var isConnected: Bool { get }
    var changes: AsyncStream<HouseholdChange> { get }
    func cancel() async
}
enum HouseholdCredentials {
    case email(String, password: String), signUp(String, password: String), google
    case password(String), passwordReset(String)
}
enum HouseholdPhotoBucket: String { case recipe = "recipe-images", profile = "profile-photos" }
struct HouseholdPhotoUpload { var path: String; var data: Data }

/// Commands describe member actions, rather than table operations. The adapter owns encoding and cleanup.
enum HouseholdMutation {
    case renameHousehold(UUID, String)
    case renameMember(household: UUID, user: UUID, name: String)
    case avatar(household: UUID, user: UUID, url: URL)
    case transferOwnership(household: UUID, user: UUID)
    case removeMember(household: UUID, user: UUID)
    case saveRecipe(Recipe, isNew: Bool, upload: HouseholdPhotoUpload?, stalePhoto: String?)
    case deleteRecipe(UUID)
    case sharing(UUID, Bool)
    case favorite(recipe: UUID, user: UUID, enabled: Bool)
    case review(RecipeReview)
    case markCooked(household: UUID, recipe: UUID, day: Date)
    case removeCooked(household: UUID, recipe: UUID, day: Date)
    case saveMeal(PlannedMeal, household: UUID, keepVersion: Bool)
    case updateMeal(UUID)
    case removeMeal(UUID)
    case saveNote(MealPlanNote, household: UUID)
    case removeNote(UUID)
}

/// A database rejection is definitive; transport failures may follow a committed household move.
struct HouseholdMoveRejected: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}

@MainActor
protocol HouseholdBackend: AnyObject {
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
