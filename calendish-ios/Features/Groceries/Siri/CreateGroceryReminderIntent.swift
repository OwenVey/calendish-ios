import AppIntents
import Foundation
import GeoToolbox
import UniformTypeIdentifiers

/// Adds a grocery when Siri on iOS 27 or later hears "Add apples to Calendish".
/// Calendish has no reminders: the household's grocery list stands in as the only list, and each grocery as a reminder on it.
@available(iOS 27, *)
@AppIntent(schema: .reminders.createReminder)
struct CreateGroceryReminderIntent {
    var title: String
    var list: GroceryListEntity?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: GroceryLocationTriggerEntity?
    var section: GrocerySectionEntity?

    @MainActor
    func perform() async throws -> some ReturnsValue<GroceryReminderEntity> & ProvidesDialog {
        guard let adder = SpokenGroceryAdd.live() else { throw GroceryReminderError.noHousehold }
        let outcomes: [SpokenGroceryAdd.Outcome]
        do { outcomes = try await adder.add([title]) }
        catch SpokenGroceryAdd.Failure.noHousehold { throw GroceryReminderError.noHousehold }
        catch { throw GroceryReminderError.unconfirmed(title) }
        guard let name = outcomes.first?.name else { throw GroceryReminderError.empty }
        return .result(value: GroceryReminderEntity(id: name, title: name), dialog: "\(SpokenGroceryAdd.reply(to: outcomes))")
    }
}

@available(iOS 27, *)
enum GroceryReminderError: Error, CustomLocalizedStringResourceConvertible {
    case noHousehold, empty, unconfirmed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noHousehold: "\(SpokenGroceryAdd.noHouseholdReply)"
        case .empty: "\(SpokenGroceryAdd.nothingToAddReply)"
        case .unconfirmed(let item): "\(SpokenGroceryAdd.failedReply(for: [item]))"
        }
    }
}

@available(iOS 27, *)
@AppEnum(schema: .reminders.listType)
enum GroceryListType: String {
    case standard

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.standard: "Standard"]
}

/// The household's grocery list, the only list Calendish offers Siri.
@available(iOS 27, *)
@AppEntity(schema: .reminders.list)
struct GroceryListEntity: UniqueAppEntity {
    static let defaultQuery = UniqueAppEntityProvider { GroceryListEntity() }
    static let groceries = GroceryListEntity()

    var name: String
    var type: GroceryListType

    init() {
        name = "Groceries"
        type = .standard
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// A grocery as Siri sees it after adding one. Only its name is meaningful.
@available(iOS 27, *)
@AppEntity(schema: .reminders.reminder)
struct GroceryReminderEntity {
    static let defaultQuery = Query()

    let id: String
    var title: String
    var note: AttributedString?
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool
    var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var list: GroceryListEntity
    var locationTrigger: GroceryLocationTriggerEntity?

    init(id: String, title: String) {
        self.id = id
        self.title = title
        tags = []
        urls = []
        isCompleted = false
        list = .groceries
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    struct Query: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [GroceryReminderEntity] {
            identifiers.map { GroceryReminderEntity(id: $0, title: $0) }
        }
    }
}

// The schema requires location triggers and sections. Groceries have neither, so Siri never finds any.

@available(iOS 27, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
enum GroceryLocationTriggerEvent: String {
    case arrive, depart

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.arrive: "Arrive", .depart: "Depart"]
}

@available(iOS 27, *)
@AppEntity(schema: .reminders.locationTrigger)
struct GroceryLocationTriggerEntity {
    static let defaultQuery = Query()

    let id: String
    var place: PlaceDescriptor
    var event: GroceryLocationTriggerEvent

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    struct Query: EntityStringQuery {
        static let persistentIdentifier = "GroceryLocationTriggerQuery"
        func entities(for identifiers: [String]) async throws -> [GroceryLocationTriggerEntity] { [] }
        func entities(matching string: String) async throws -> [GroceryLocationTriggerEntity] { [] }
    }
}

@available(iOS 27, *)
@AppEntity(schema: .reminders.section)
struct GrocerySectionEntity {
    static let defaultQuery = Query()

    let id: String
    var name: String
    var list: GroceryListEntity

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    struct Query: EntityStringQuery {
        static let persistentIdentifier = "GrocerySectionQuery"
        func entities(for identifiers: [String]) async throws -> [GrocerySectionEntity] { [] }
        func entities(matching string: String) async throws -> [GrocerySectionEntity] { [] }
    }
}
