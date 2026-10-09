import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A planned meal dragged between days. Declared in Info.plist so drags stay within Calendish.
    nonisolated static let plannedMeal = UTType(exportedAs: "owenvey.calendish-ios.planned-meal")
}

/// A planned meal or note being dragged to another day.
nonisolated struct PlannedMealDrag: Codable, Transferable {
    let entryID: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plannedMeal)
    }
}

struct MealSelection: Identifiable {
    let id = UUID()
    var date = Calendar.current.startOfDay(for: .now)
    var meal: PlannedMeal?
    /// A recipe to preselect when planning from a recipe page.
    var recipeID: UUID?
}

/// Planned meals and notes whose ingredients and items to review before adding them to groceries.
private struct GroceryReview: Identifiable {
    let id = UUID()
    var meals: [PlannedMeal]
    var notes: [MealPlanNote]
    var candidates: [GroceryImportCandidate] { GroceryImportCandidate.planned(meals) + GroceryImportCandidate.noted(notes) }
}

/// Planned meals and notes to remove once confirmed.
private struct PlanRemoval {
    var meals: [PlannedMeal] = []
    var notes: [MealPlanNote] = []
    var isEmpty: Bool { meals.isEmpty && notes.isEmpty }

    var title: String {
        switch (meals.count, notes.count) {
        case (0, 1): "Remove This Note?"
        case (0, _): "Remove These Notes?"
        case (1, 0): "Remove This Planned Meal?"
        case (_, 0): "Remove These Planned Meals?"
        default: "Clear This Day?"
        }
    }
    var buttonTitle: String {
        switch (meals.count, notes.count) {
        case (0, 1): "Remove Note"
        case (0, _): "Remove Notes"
        case (1, 0): "Remove Meal"
        case (_, 0): "Remove Meals"
        default: "Clear Day"
        }
    }
    var message: String? {
        switch meals.count {
        case 0: nil
        case 1: "The recipe stays in your recipe book."
        default: "The recipes stay in your recipe book."
        }
    }
}

/// Days from the start of this week onward, each with the recipes planned for it. More days load as you
/// scroll toward the end, and pulling down past the top loads the previous week.
struct MealPlanView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var firstDay = CalendarDays.startOfWeek(.now)
    /// Always whole weeks, so the list starts and ends on week boundaries.
    @State private var weekCount = 4
    @State private var selection: MealSelection?
    @State private var groceryReview: GroceryReview?
    @State private var editingNote: MealPlanNote?
    @State private var removing = PlanRemoval()
    /// How far the list is pulled down past its top.
    @State private var pullDistance: CGFloat = 0
    private static let pageSize = 4
    private static let pullThreshold: CGFloat = 70
    private var isPullArmed: Bool { pullDistance >= Self.pullThreshold }

    private var weeks: [Date] {
        (0..<weekCount).map { Calendar.current.date(byAdding: .weekOfYear, value: $0, to: firstDay)! }
    }

    var body: some View {
        let calendar = Calendar.current
        let mealsByDay = Dictionary(grouping: store.meals) { calendar.startOfDay(for: $0.date) }
        let notesByDay = Dictionary(grouping: store.notes) { calendar.startOfDay(for: $0.date) }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(weeks, id: \.self) { week in
                        let isThisWeek = calendar.isDate(week, inSameDayAs: CalendarDays.startOfWeek(.now))
                        Section {
                            ForEach(CalendarDays.week(containing: week), id: \.self) { day in
                                let meals = mealsByDay[day, default: []]
                                let notes = notesByDay[day, default: []]
                                MealPlanDay(day: day, meals: meals, notes: notes, isThisWeek: isThisWeek,
                                            add: { selection = MealSelection(date: day) },
                                            edit: { selection = MealSelection(date: day, meal: $0) },
                                            addNote: { editingNote = MealPlanNote(date: day, text: "") },
                                            editNote: { editingNote = $0 },
                                            remove: { removing = $0 },
                                            move: { ids in
                                                let movingMeals = store.meals.filter { ids.contains($0.id) }
                                                let movingNotes = store.notes.filter { ids.contains($0.id) }
                                                withAnimation(reduceMotion ? nil : .snappy) {
                                                    movingMeals.forEach { store.moveMeal($0, to: day) }
                                                    movingNotes.forEach { store.moveNote($0, to: day) }
                                                }
                                            },
                                            addToGroceries: { groceryReview = GroceryReview(meals: meals, notes: notes) })
                                    .id(day)
                            }
                        } header: {
                            WeekHeader(week: week)
                                .onAppear { if week == weeks.last { weekCount += Self.pageSize } }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                // Sits just above the first week, so it's revealed in the gap as the list is pulled down.
                .background(alignment: .top) {
                    PullForEarlierWeek(isArmed: isPullArmed)
                        .opacity(min(1, pullDistance / Self.pullThreshold))
                        .alignmentGuide(.top) { $0[.bottom] }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, distance in
                pullDistance = distance
            }
            .onScrollPhaseChange { old, new in
                if old == .interacting, new != .interacting, isPullArmed { loadPreviousWeek() }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPullArmed) { _, armed in armed }
            .accessibilityAction(named: "Load Previous Week", loadPreviousWeek)
            .background(CalendishStyle.background)
            .navigationTitle("Meal Plan")
            .tabRootStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(calendar.startOfDay(for: .now), anchor: .top) }
                    }
                    .toolbarGlyph()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Section("Add to Groceries") {
                            Button("This Week", systemImage: "calendar.day.timeline.left") { reviewGroceries(weeksFromNow: 0) }
                            Button("Next Week", systemImage: "calendar.day.timeline.right") { reviewGroceries(weeksFromNow: 1) }
                        }
                    }
                    .menuStyle(CalendishMenuStyle())
                }
            }
        }
        .onChange(of: weekStart) { _, _ in
            firstDay = CalendarDays.startOfWeek(.now)
            weekCount = Self.pageSize
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .sheet(item: $selection) { MealPickerView(selection: $0) }
        .sheet(item: $groceryReview) { GroceryImportReviewView(candidates: $0.candidates) }
        .sheet(item: $editingNote) { MealNoteEditor(note: $0) }
        .calendishAlert(removing.title, isPresented: Binding(get: { !removing.isEmpty }, set: { if !$0 { removing = PlanRemoval() } })) {
            Button(removing.buttonTitle, role: .destructive) {
                removing.meals.forEach(store.removeMeal)
                removing.notes.forEach(store.removeNote)
                removing = PlanRemoval()
            }
            Button("Cancel", role: .cancel) { removing = PlanRemoval() }
        } message: { if let message = removing.message { Text(message) } }
    }

    private func loadPreviousWeek() {
        withAnimation(reduceMotion ? nil : .snappy) {
            firstDay = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: firstDay)!
            weekCount += 1
        }
    }

    private func reviewGroceries(weeksFromNow: Int) {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: weeksFromNow, to: CalendarDays.startOfWeek(.now))!
        let days = CalendarDays.week(containing: start)
        let isInWeek = { (date: Date) in days.contains { Calendar.current.isDate($0, inSameDayAs: date) } }
        groceryReview = GroceryReview(meals: store.meals.filter { isInWeek($0.date) }, notes: store.notes.filter { isInWeek($0.date) })
    }
}

/// The hint revealed above the first week while pulling the meal plan down.
private struct PullForEarlierWeek: View {
    let isArmed: Bool

    var body: some View {
        Label(isArmed ? "Release to Load Previous Week" : "Pull to Load Previous Week", systemImage: "arrow.down")
            .labelStyle(PullHintLabelStyle(isArmed: isArmed))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
            .animation(.snappy, value: isArmed)
            .accessibilityHidden(true)
    }
}

private struct PullHintLabelStyle: LabelStyle {
    let isArmed: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.rotationEffect(.degrees(isArmed ? 180 : 0))
            configuration.title.contentTransition(.opacity)
        }
    }
}

/// One day in the meal plan: a header with actions, then its recipes and notes.
private struct MealPlanDay: View {
    @Environment(HouseholdStore.self) private var store
    let day: Date
    let meals: [PlannedMeal]
    let notes: [MealPlanNote]
    /// Days in the current week are solid cards; other weeks recede, and their empty days shrink to a single row.
    let isThisWeek: Bool
    let add: () -> Void
    let edit: (PlannedMeal) -> Void
    let addNote: () -> Void
    let editNote: (MealPlanNote) -> Void
    let remove: (PlanRemoval) -> Void
    /// Moves dropped meals and notes here.
    let move: ([UUID]) -> Void
    let addToGroceries: () -> Void
    @State private var isDropTarget = false
    @State private var dropCount = 0
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isEmpty: Bool { meals.isEmpty && notes.isEmpty }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            header
            if isEmpty && isThisWeek {
                Button(action: add) {
                    Text("Nothing planned — tap to add a recipe")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Recipe")
            } else {
                mealRows
                noteRows
            }
        }
        .padding(6)
        .padding(.bottom, isEmpty && !isThisWeek ? 0 : 4)
        .background(isThisWeek ? CalendishStyle.surface : .clear, in: shape)
        .overlay {
            if isDropTarget {
                shape.fill(CalendishStyle.accent.opacity(0.08))
                shape.strokeBorder(CalendishStyle.accent, lineWidth: 2)
            } else if isToday {
                shape.strokeBorder(CalendishStyle.accent.opacity(0.7), lineWidth: 1.5)
            } else if !isThisWeek {
                shape.strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
        .dropDestination(for: PlannedMealDrag.self) { items, _ in
            let ids = items.map(\.entryID).filter { id in !meals.contains { $0.id == id } && !notes.contains { $0.id == id } }
            guard !ids.isEmpty else { return false }
            move(ids)
            dropCount += 1
            return true
        } isTargeted: { isDropTarget = $0 }
        .animation(.snappy(duration: 0.2), value: isDropTarget)
        .sensoryFeedback(.success, trigger: dropCount)
    }

    private var mealRows: some View {
        ForEach(meals) { meal in
            NavigationLink { RecipeDetailView(recipe: meal.recipe, plannedMeal: meal) } label: {
                RecipeRow(recipe: meal.recipe, servings: meal.servings)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .draggable(PlannedMealDrag(entryID: meal.id)) {
                RecipeRow(recipe: meal.recipe, servings: meal.servings)
                    .padding(10)
                    .frame(width: 320, alignment: .leading)
                    .background(CalendishStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
                    // Drag previews render outside the view hierarchy, so they don't inherit the environment.
                    .environment(store)
            }
            .calendishContextMenu {
                Button("Edit Meal", systemImage: "pencil") { edit(meal) }
                Button("Remove Meal", systemImage: "trash", role: .destructive) { remove(PlanRemoval(meals: [meal])) }
            }
            .accessibilityAction(named: "Edit Meal") { edit(meal) }
            .accessibilityAction(named: "Remove Meal") { remove(PlanRemoval(meals: [meal])) }
        }
    }

    private var noteRows: some View {
        ForEach(notes) { note in
            Button { editNote(note) } label: {
                MealNoteRow(note: note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .accessibilityHint("Edits the note")
            .draggable(PlannedMealDrag(entryID: note.id)) {
                MealNoteRow(note: note)
                    .padding(10)
                    .frame(width: 320, alignment: .leading)
                    .background(CalendishStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
            }
            .calendishContextMenu {
                Button("Edit Note", systemImage: "pencil") { editNote(note) }
                Button("Remove Note", systemImage: "trash", role: .destructive) { remove(PlanRemoval(notes: [note])) }
            }
            .accessibilityAction(named: "Remove Note") { remove(PlanRemoval(notes: [note])) }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("\(Text(day.formatted(.dateTime.weekday(.wide))).foregroundStyle(isToday ? CalendishStyle.accent : Color.primary)) \(Text(day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(.secondary))")
                .font(.headline)
                .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button("Add Recipe", systemImage: "book.closed", action: add)
                Button("Add Note", systemImage: "note.text", action: addNote)
            } label: {
                Label("Add to \(day.formatted(.dateTime.weekday(.wide)))", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(CalendishMenuStyle())
            Menu {
                Button("Add to Groceries", systemImage: "basket", action: addToGroceries)
                    .disabled(meals.isEmpty && !notes.contains { !$0.items.isEmpty })
                if !isEmpty {
                    Button(notes.isEmpty ? "Remove All Meals" : "Clear Day", systemImage: "trash", role: .destructive) {
                        remove(PlanRemoval(meals: meals, notes: notes))
                    }
                }
            } label: {
                // A Menu only hit-tests its label, so the 44pt target has to live inside it.
                Label("More for \(day.formatted(.dateTime.weekday(.wide)))", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(CalendishMenuStyle())
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .tint(.primary)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(Color(isThisWeek ? .tertiarySystemFill : .quaternarySystemFill), in: .capsule)
    }
}

/// Names the week, like Calendar's list view: relative names nearby, dates further out.
private struct WeekHeader: View {
    let week: Date

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = CalendarDays.startOfWeek(.now)
        let offset = calendar.dateComponents([.weekOfYear], from: thisWeek, to: week).weekOfYear ?? 0
        let end = calendar.date(byAdding: .day, value: 6, to: week)!
        let sameYear = calendar.isDate(week, equalTo: .now, toGranularity: .year) && calendar.isDate(end, equalTo: .now, toGranularity: .year)
        let range = (week..<end).formatted(sameYear ? .interval.month(.abbreviated).day() : .interval.month(.abbreviated).day().year())
        let name: String? = switch offset {
        case -1: "Last Week"
        case 0: "This Week"
        case 1: "Next Week"
        default: nil
        }
        HStack(alignment: .firstTextBaseline) {
            Text(name ?? range).font(.title3.weight(.semibold))
            Spacer()
            if name != nil { Text(range).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct MealPickerView: View {
    let selection: MealSelection
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var recipeID: UUID?
    @State private var keepsSavedVersion = true
    @State private var servings = 4
    @State private var date = Date.now
    @State private var initialValues: String?
    @State private var discardChanges = false
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    private var values: String { "\(keepsSavedVersion)|\(recipeID?.uuidString ?? "")|\(servings)|\(date.timeIntervalSince1970)" }
    private var isDirty: Bool { initialValues != nil && values != initialValues }
    private var recipes: [Recipe] { store.recipes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }

    private var recipeChoices: some View {
                Section("Choose a recipe") {
                    ForEach(recipes) { recipe in
                        Button {
                            keepsSavedVersion = false
                            recipeID = recipe.id
                            servings = recipe.servings
                        } label: {
                            HStack {
                                RecipeRow(recipe: recipe)
                                Spacer()
                                if recipeID == recipe.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent).accessibilityHidden(true) }
                            }
                        }.buttonStyle(.plain)
                            .accessibilityValue(recipeID == recipe.id ? "Selected" : "Not selected")
                            .accessibilityAddTraits(recipeID == recipe.id ? .isSelected : [])
                    }
                    if recipes.isEmpty {
                        ContentUnavailableView(store.recipes.isEmpty ? "Add a Recipe First" : "No Matching Recipes", systemImage: "book.closed", description: Text(store.recipes.isEmpty ? "Open Recipes and tap + to add your first dish." : "Try another search."))
                    }
                }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                    ServingsField(servings: $servings)
                }
                if let meal = selection.meal {
                    Section {
                        RecipeRow(recipe: meal.recipe, servings: meal.servings)
                        Toggle("Keep saved version", isOn: $keepsSavedVersion)
                    } header: { Text("Saved recipe version") } footer: { Text("Keep the planned ingredients and instructions when changing the day or servings. Turn this off to choose a current recipe.") }
                }
                recipeChoices
            }
            .searchable(text: $search, prompt: "Find a recipe")
            .navigationTitle(selection.meal == nil ? "Add Recipe" : "Edit Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard Meal Changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if keepsSavedVersion, let meal = selection.meal {
                            store.saveMeal(date: date, recipe: meal.recipe, servings: servings, editing: meal, keepVersion: true)
                            dismiss()
                        } else if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
                            store.saveMeal(date: date, recipe: recipe, servings: servings, editing: selection.meal)
                            dismiss()
                        }
                    } label: { OnAccentLabel(title: "Save") }.disabled(!(keepsSavedVersion && selection.meal != nil) && recipeID == nil)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialValues == nil else { return }
                recipeID = selection.meal?.recipeID ?? selection.recipeID
                servings = selection.meal?.servings ?? store.recipes.first { $0.id == recipeID }?.servings ?? PreferenceKey.servingsForNewRecipes
                date = selection.date
                initialValues = values
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }
}

/// A meal plan note, laid out like a recipe row so a day's entries line up.
private struct MealNoteRow: View {
    let note: MealPlanNote

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill))
                Image(systemName: "note.text").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(note.text).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if !note.items.isEmpty {
                    Label(note.items.formatted(.list(type: .and, width: .narrow)), systemImage: "basket")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityLabel("Groceries: \(note.items.formatted())")
                }
            }.padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Adds a note to a day, or edits one, with optional grocery items.
private struct MealNoteEditor: View {
    /// A grocery item line with a stable identity while editing.
    private struct Item: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    let note: MealPlanNote
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var text = ""
    @State private var date = Date.now
    @State private var items: [Item] = []
    @State private var initialValues: String?
    @State private var discardChanges = false
    @State private var confirmRemoval = false
    @FocusState private var focusedItem: UUID?
    @FocusState private var textFocused: Bool
    private static let suggestions = ["Leftovers", "Eating Out", "Takeout", "Fend for Yourself"]
    private var isNew: Bool { !store.notes.contains { $0.id == note.id } }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var values: String { ([text, "\(date.timeIntervalSince1970)"] + items.map(\.text)).joined(separator: "|") }
    private var isDirty: Bool { initialValues != nil && values != initialValues }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Note", text: $text, prompt: Text("Leftovers, dinner out…"))
                        .focused($textFocused)
                        .submitLabel(.done)
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                } footer: {
                    if isNew && trimmedText.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(Self.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { text = suggestion }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                                    .tint(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                Section {
                    ForEach($items) { $item in
                        TextField("Item", text: $item.text, prompt: Text("Baguette"))
                            .focused($focusedItem, equals: item.id)
                            .submitLabel(.next)
                            .onSubmit(addItem)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button("Add Item", systemImage: "plus", action: addItem)
                } header: { Text("Groceries") } footer: {
                    Text("Included when you add this day’s meals to your grocery list.")
                }
                if !isNew {
                    Section {
                        Button("Remove Note", role: .destructive) { confirmRemoval = true }
                            .frame(maxWidth: .infinity)
                            .confirmationDialog("Remove This Note?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                                Button("Remove Note", role: .destructive) {
                                    store.removeNote(note)
                                    dismiss()
                                }
                            }
                    }
                }
            }
            .navigationTitle(isNew ? "Add Note" : "Edit Note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard Note Changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { OnAccentLabel(title: "Save") }
                        .disabled(trimmedText.isEmpty)
                        .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialValues == nil else { return }
                text = note.text
                date = note.date
                items = note.items.map { Item(text: $0) }
                initialValues = values
                if isNew { textFocused = true }
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }

    private func addItem() {
        // Reuse a blank line rather than piling up empty ones.
        if let blank = items.first(where: { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            focusedItem = blank.id
            return
        }
        let item = Item(text: "")
        items.append(item)
        focusedItem = item.id
    }

    private func save() {
        store.saveNote(MealPlanNote(id: note.id, date: date, text: text, items: items.map(\.text)))
        dismiss()
    }
}
