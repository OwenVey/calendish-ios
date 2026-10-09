import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A planned meal dragged between days. Declared in Info.plist so drags stay within Calendish.
    nonisolated static let plannedMeal = UTType(exportedAs: "owenvey.calendish-ios.planned-meal")
}

/// A planned meal being dragged to another day.
nonisolated struct PlannedMealDrag: Codable, Transferable {
    let mealID: UUID
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

/// Planned meals whose ingredients to review before adding them to groceries.
private struct GroceryReview: Identifiable {
    let id = UUID()
    var meals: [PlannedMeal]
}

/// Days from the start of this week onward, each with the recipes planned for it. More days load as you
/// scroll toward the end, and earlier weeks load on request.
struct MealPlanView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var firstDay = CalendarDays.startOfWeek(.now)
    /// Always whole weeks, so the list starts and ends on week boundaries.
    @State private var weekCount = 4
    @State private var selection: MealSelection?
    @State private var groceryReview: GroceryReview?
    @State private var removing: [PlannedMeal] = []
    private static let pageSize = 4

    private var weeks: [Date] {
        (0..<weekCount).map { Calendar.current.date(byAdding: .weekOfYear, value: $0, to: firstDay)! }
    }

    var body: some View {
        let calendar = Calendar.current
        let mealsByDay = Dictionary(grouping: store.meals) { calendar.startOfDay(for: $0.date) }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    Button("Show Earlier Weeks", systemImage: "chevron.up") {
                        // Slide the earlier week in under the button instead of snapping the list down a screen.
                        withAnimation(reduceMotion ? nil : .snappy) {
                            firstDay = calendar.date(byAdding: .weekOfYear, value: -1, to: firstDay)!
                            weekCount += 1
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    ForEach(weeks, id: \.self) { week in
                        let isThisWeek = calendar.isDate(week, inSameDayAs: CalendarDays.startOfWeek(.now))
                        Section {
                            ForEach(CalendarDays.week(containing: week), id: \.self) { day in
                                let meals = mealsByDay[day, default: []]
                                MealPlanDay(day: day, meals: meals, isThisWeek: isThisWeek,
                                            add: { selection = MealSelection(date: day) },
                                            edit: { selection = MealSelection(date: day, meal: $0) },
                                            remove: { removing = $0 },
                                            move: { ids in
                                                let moving = store.meals.filter { ids.contains($0.id) }
                                                withAnimation(reduceMotion ? nil : .snappy) { moving.forEach { store.moveMeal($0, to: day) } }
                                            },
                                            addToGroceries: { groceryReview = GroceryReview(meals: meals) })
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
            }
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
        .sheet(item: $groceryReview) { GroceryImportReviewView(candidates: GroceryImportCandidate.planned($0.meals)) }
        .calendishAlert(removing.count > 1 ? "Remove These Planned Meals?" : "Remove This Planned Meal?",
                        isPresented: Binding(get: { !removing.isEmpty }, set: { if !$0 { removing = [] } })) {
            Button(removing.count > 1 ? "Remove Meals" : "Remove Meal", role: .destructive) {
                removing.forEach(store.removeMeal)
                removing = []
            }
            Button("Cancel", role: .cancel) { removing = [] }
        } message: { Text(removing.count > 1 ? "The recipes stay in your recipe book." : "The recipe stays in your recipe book.") }
    }

    private func reviewGroceries(weeksFromNow: Int) {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: weeksFromNow, to: CalendarDays.startOfWeek(.now))!
        let days = CalendarDays.week(containing: start)
        groceryReview = GroceryReview(meals: store.meals.filter { meal in days.contains { Calendar.current.isDate($0, inSameDayAs: meal.date) } })
    }
}

/// One day in the meal plan: a header with actions, then its recipes.
private struct MealPlanDay: View {
    @Environment(HouseholdStore.self) private var store
    let day: Date
    let meals: [PlannedMeal]
    /// Days in the current week are solid cards; other weeks recede, and their empty days shrink to a single row.
    let isThisWeek: Bool
    let add: () -> Void
    let edit: (PlannedMeal) -> Void
    let remove: ([PlannedMeal]) -> Void
    /// Moves dropped meals here.
    let move: ([UUID]) -> Void
    let addToGroceries: () -> Void
    @State private var isDropTarget = false
    @State private var dropCount = 0
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            header
            if meals.isEmpty && isThisWeek {
                Button(action: add) {
                    Text("No recipes — tap to add")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Recipe")
            } else {
                ForEach(meals) { meal in
                    NavigationLink { RecipeDetailView(recipe: meal.recipe, plannedMeal: meal) } label: {
                        RecipeRow(recipe: meal.recipe, servings: meal.servings)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .draggable(PlannedMealDrag(mealID: meal.id)) {
                        RecipeRow(recipe: meal.recipe, servings: meal.servings)
                            .padding(10)
                            .frame(width: 320, alignment: .leading)
                            .background(CalendishStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
                            // Drag previews render outside the view hierarchy, so they don't inherit the environment.
                            .environment(store)
                    }
                    .calendishContextMenu {
                        Button("Edit Meal", systemImage: "pencil") { edit(meal) }
                        Button("Remove Meal", systemImage: "trash", role: .destructive) { remove([meal]) }
                    }
                    .accessibilityAction(named: "Edit Meal") { edit(meal) }
                    .accessibilityAction(named: "Remove Meal") { remove([meal]) }
                }
            }
        }
        .padding(6)
        .padding(.bottom, meals.isEmpty && !isThisWeek ? 0 : 4)
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
            let ids = items.map(\.mealID).filter { id in !meals.contains { $0.id == id } }
            guard !ids.isEmpty else { return false }
            move(ids)
            dropCount += 1
            return true
        } isTargeted: { isDropTarget = $0 }
        .animation(.snappy(duration: 0.2), value: isDropTarget)
        .sensoryFeedback(.success, trigger: dropCount)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("\(Text(day.formatted(.dateTime.weekday(.wide))).foregroundStyle(isToday ? CalendishStyle.accent : Color.primary)) \(Text(day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(.secondary))")
                .font(.headline)
                .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Add Recipe", systemImage: "plus", action: add)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            Menu {
                Button("Add to Groceries", systemImage: "basket", action: addToGroceries)
                    .disabled(meals.isEmpty)
                if !meals.isEmpty {
                    Button("Remove All Meals", systemImage: "trash", role: .destructive) { remove(meals) }
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
