import SwiftUI

struct RecipeEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RecipeDraftEditing
    private let isImported: Bool
    private let importedWithoutIngredients: Bool
    private let importedWithoutInstructions: Bool
    @State private var discardChanges = false
    @FocusState private var isTagFieldFocused: Bool
    @FocusState private var focusedIngredient: Ingredient.ID?
    @FocusState private var focusedStep: RecipeDraftEditing.Step.ID?

    init(recipe: Recipe? = nil, imported: ImportedRecipe? = nil) {
        isImported = imported != nil
        importedWithoutIngredients = imported?.recipe.ingredients.isEmpty == true
        importedWithoutInstructions = imported?.recipe.steps.isEmpty == true
        _editing = State(initialValue: RecipeDraftEditing(recipe: recipe, imported: imported,
            defaultServings: PreferenceKey.servingsForNewRecipes, sharesNewRecipes: PreferenceKey.sharesNewRecipes))
    }
    var body: some View {
        @Bindable var editing = editing
        NavigationStack {
            Form {
                if isImported {
                    Section {
                        Text("Check the ingredients, steps, and servings before saving.")
                        if importedWithoutIngredients && !editing.fields.ingredients.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Text("No ingredients were imported.")
                        }
                        if importedWithoutInstructions && !editing.fields.steps.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Text("No instructions were imported.")
                        }
                    }
                }
                Section {
                    TextField("Recipe title", text: $editing.fields.title)
                        .font(.title3.weight(.semibold))
                    ServingsField(servings: $editing.fields.servings)
                    RecipeDurationField(title: "Prep time", minutes: $editing.fields.prepMinutes)
                    RecipeDurationField(title: "Cook time", minutes: $editing.fields.cookMinutes)
                } footer: {
                    if !editing.canSave { Text("To save, add a title and at least one ingredient or instruction.") }
                }
                Section {
                    PhotoSourceMenu(hasPhoto: editing.hasPhoto, onPick: editing.setPhoto, onRemove: { editing.setPhoto(nil) }) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                                if let newPhoto = editing.photo {
                                    Image(uiImage: newPhoto).resizable().scaledToFill()
                                } else if let keptPhotoPath = editing.keptPhotoPath {
                                    RecipePhoto(path: keptPhotoPath)
                                } else {
                                    Image(systemName: "camera").font(.title3).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 10))
                            Text(editing.hasPhoto ? "Edit photo" : "Add photo")
                                .foregroundStyle(CalendishStyle.accent)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editing.hasPhoto ? "Edit photo" : "Add photo")
                }
                Section {
                    ForEach($editing.fields.ingredients) { $ingredient in
                        TextField("e.g. 2 cups flour", text: $ingredient.text)
                            .focused($focusedIngredient, equals: ingredient.id)
                            .submitLabel(.next)
                            .onSubmit { addIngredient(after: ingredient.id) }
                    }
                    .onMove { source, destination in
                        editing.fields.ingredients.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        editing.fields.ingredients.remove(atOffsets: offsets)
                    }

                    Button("Add ingredient", systemImage: "plus.circle.fill") {
                        addIngredient(after: editing.fields.ingredients.last?.id)
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Add ingredients here. Drag the handles to reorder.")
                }
                Section {
                    ForEach($editing.fields.steps) { $step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\((editing.fields.steps.firstIndex { $0.id == step.id } ?? 0) + 1).")
                                .monospacedDigit().foregroundStyle(.secondary)
                            TextField("Describe this step", text: $step.text, axis: .vertical)
                                .lineLimit(3...8)
                                .focused($focusedStep, equals: step.id)
                        }
                    }
                    .onMove { source, destination in
                        editing.fields.steps.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        editing.fields.steps.remove(atOffsets: offsets)
                    }

                    Button("Add step", systemImage: "plus.circle.fill") {
                        let step = RecipeDraftEditing.Step()
                        editing.fields.steps.append(step)
                        focusedStep = step.id
                    }
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Add cooking steps here. Drag the handles to reorder.")
                }
                Section("Details") {
                    LabeledFormField("Description") {
                        TextField("A little about this recipe", text: $editing.fields.summary, axis: .vertical)
                    }
                    LabeledFormField("Source link") {
                        TextField("https://", text: $editing.fields.sourceLink)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Picker("Category", selection: $editing.fields.category) {
                        Text("None").tag(RecipeCategory?.none)
                        ForEach(RecipeCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(Optional(category))
                        }
                    }
                    .tint(.secondary)
                    LabeledFormField("Makes") {
                        TextField("24 cookies", text: $editing.fields.yieldText)
                    }
                }
                Section {
                    if !editing.fields.tags.isEmpty {
                        FlowLayout {
                            ForEach(editing.fields.tags, id: \.self) { tag in
                                Button { withAnimation(reduceMotion ? nil : .default) { editing.fields.tags.removeAll { $0 == tag } } } label: {
                                    TagPill(tag: tag, systemImage: "xmark").frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    TextField("Add a tag", text: $editing.fields.newTag)
                        .focused($isTagFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            guard addTag(editing.fields.newTag) else { return }
                            isTagFieldFocused = true
                        }
                    if !tagSuggestions.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    Button { addTag(tag) } label: { TagPill(tag: tag, systemImage: "plus", muted: true).frame(minHeight: 44) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Add tag \(tag)")
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    if !editing.fields.tags.isEmpty { Text("Tap a tag to remove it.") }
                }
                if editing.isNew {
                    Section {
                        Toggle("Share with household", isOn: $editing.fields.isShared)
                    } footer: {
                        Text(editing.fields.isShared ? "Your household will be able to see and cook this recipe. Only you will be able to edit it." : "This recipe will be private.")
                    }
                }
            }
            // Always editing, so ingredient and step rows show the delete control and drag handle.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(isImported ? "Review recipe" : editing.isNew ? "New recipe" : "Edit recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editing.isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard recipe changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { editing.discard(); dismiss() }
                            Button("Keep editing") { }
                        } message: { Text("Your draft stays on this device until you save or discard it.") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if editing.save(knownTags: store.recipeTags, using: { recipe, photo, onSaved in
                            store.saveRecipe(recipe, photo: photo, onSaved: onSaved)
                        }) { dismiss() }
                    } label: { OnAccentLabel(title: "Save") }
                    .disabled(!editing.canSave)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
        }
        .background { DraftDismissalGuard(isDirty: editing.isDirty && !editing.isClosing) { discardChanges = true } }
        .onAppear { editing.open(accountID: store.userID) }
        .onChange(of: store.userID) { _, account in editing.open(accountID: account) }
    }
    private var tagSuggestions: [String] { editing.tagSuggestions(in: store.recipeTags) }

    @discardableResult
    private func addTag(_ text: String) -> Bool {
        withAnimation(reduceMotion ? nil : .default) { editing.addTag(text, knownTags: store.recipeTags) }
    }

    private func addIngredient(after id: Ingredient.ID?) {
        focusedIngredient = editing.addIngredient(after: id)
    }
}
