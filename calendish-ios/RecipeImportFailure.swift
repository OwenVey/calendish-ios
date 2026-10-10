import SwiftUI

/// Why a recipe couldn't be read, offering any recognized text to fix up by hand.
struct RecipeImportFailure: View {
    let message: String
    let recognizedText: String?
    let onEditText: (String) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t read recipe", systemImage: "text.viewfinder")
        } description: {
            Text(message)
        } actions: {
            if let recognizedText {
                Button("Edit text") { onEditText(recognizedText) }
                    .modifier(GlassActionStyle(prominent: true))
            }
        }
    }
}
