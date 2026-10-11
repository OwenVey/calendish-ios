import SwiftUI

/// The link and text import forms: a field to fill or paste into, then Import.
/// A link pasted as text is still imported as a link.
struct RecipeImportComposeForm<Field: View, Header: View, Footer: View>: View {
    let title: String
    @Binding var draft: String
    let error: String?
    let onImport: (String) -> Void
    let onPaste: ([RecipeImport]) -> Void
    let onClear: () -> Void
    @ViewBuilder let field: Field
    @ViewBuilder let header: Header
    @ViewBuilder let footer: Footer
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    private var isEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                            .accessibilityIdentifier("Recipe import error")
                    }
                }
                Section {
                    field
                } header: {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            header.fixedSize(horizontal: false, vertical: true)
                            pasteButton
                        }
                    } else {
                        HStack {
                            header
                            Spacer()
                            pasteButton
                        }
                    }
                } footer: {
                    footer
                }
                Section {
                    Button { onImport(draft) } label: {
                        Text("Import")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .disabled(isEmpty)
                    .modifier(GlassActionStyle(prominent: true))
                    .controlSize(.large)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
            .listSectionSpacing(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.toolbarGlyph()
                }
                if !draft.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", systemImage: "xmark.circle", action: onClear).toolbarGlyph()
                    }
                }
            }
        }
    }
    private var pasteButton: some View {
        // Accepts a link, text, an image, or a PDF, without the paste permission prompt.
        PasteButton(payloadType: RecipeImport.self) { items in
            Task { @MainActor in onPaste(items) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        // The native paste control clips its label at the largest accessibility sizes.
        // Keep its label enlarged and readable while the rest of the form scales fully.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .fixedSize()
    }
}
