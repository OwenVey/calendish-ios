import PhotosUI
import SwiftUI

/// The internal source-reading adapter. Production uses the existing on-device importers;
/// workflow tests control loading and reading without platform pickers or model availability.
@MainActor
struct RecipeImportReader {
    var photo: @MainActor (PhotosPickerItem) async throws -> Data?
    var file: @MainActor (URL) async throws -> Data
    var link: @MainActor (URL, String?) async throws -> ImportedRecipe
    var text: @MainActor (String) async throws -> ImportedRecipe
    var images: @MainActor ([Data]) async throws -> String
    var pdf: @MainActor (Data) async throws -> String

    static let onDevice = RecipeImportReader(
        photo: { try await $0.loadTransferable(type: Data.self) },
        file: { try await ImportFileReader.shared.read($0) },
        link: { try await RecipeLinkImporter.fetch($0, sharedText: $1) },
        text: { try await RecipeTextImporter.parse($0) },
        images: { try await RecipeImageImporter.text(in: $0) },
        pdf: { try await RecipePDFImporter.text(in: $0) }
    )
}
