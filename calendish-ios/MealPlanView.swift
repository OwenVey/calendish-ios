import SwiftUI

struct MealSelection: Identifiable {
    let id = UUID()
    var date: Date
    var slot: MealSlot
    var meal: PlannedMeal?
    /// A recipe to preselect when planning from a recipe page.
    var recipeID: UUID?

    /// Plans a recipe for the next open slot on the planning day, or its last slot when all are taken.
    static func planning(_ recipe: Recipe, store: HouseholdStore, enabledSlots: String) -> MealSelection {
        let date = store.planningDate
        let slots = MealSlot.enabled(in: enabledSlots)
        let slot = slots.first { store.meal(on: date, slot: $0) == nil } ?? slots.last!
        return MealSelection(date: date, slot: slot, recipeID: recipe.id)
    }
}

enum GroceryReviewPeriod: String, Identifiable {
    case week, month
    var id: Self { self }
}

struct MealPlanView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: MealSelection?
    @State private var reviewPeriod: GroceryReviewPeriod?
    @State private var removing: PlannedMeal?
    @State private var showCalendar = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @AppStorage(MealSlot.enabledStorageKey) private var enabledSlots = MealSlot.allEnabled
    /// Turned-off slots still appear on days that already have a meal in them.
    private var visibleSlots: [MealSlot] {
        let enabled = MealSlot.enabled(in: enabledSlots)
        return MealSlot.allCases.filter { enabled.contains($0) || store.meal(on: store.planningDate, slot: $0) != nil }
    }

    var body: some View {
        List {
            if typeSize.isAccessibilitySize {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("Planning Day", selection: Binding(get: { store.planningDate }, set: { store.planningDate = Calendar.current.startOfDay(for: $0) }), in: CalendarDays.plannableRange, displayedComponents: .date)
                        ForEach(CalendarDays.week(containing: store.planningDate), id: \.self) { day in
                            let selected = Calendar.current.isDate(day, inSameDayAs: store.planningDate)
                            Button { store.planningDate = day } label: {
                                Label {
                                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? CalendishStyle.accent : Color.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityValue(dayStatus(day))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }

            Section {
                ForEach(visibleSlots) { slot in
                    VStack(alignment: .leading, spacing: 16) {
                        Label(slot.title, systemImage: slot.symbol).font(.subheadline).foregroundStyle(.secondary)
                        if let meal = store.meal(on: store.planningDate, slot: slot) {
                            let recipe = meal.recipe
                            NavigationLink { RecipeDetailView(recipe: recipe, plannedMeal: meal) } label: { RecipeRow(recipe: recipe, servings: meal.servings) }
                                .calendishContextMenu {
                                    Button("Edit \(slot.title)", systemImage: "pencil") { selection = MealSelection(date: store.planningDate, slot: slot, meal: meal) }
                                }
                                .accessibilityAction(named: "Edit \(slot.title)") { selection = MealSelection(date: store.planningDate, slot: slot, meal: meal) }
                        } else {
                            Button {
                                selection = MealSelection(date: store.planningDate, slot: slot)
                            } label: {
                                Label("Plan \(slot.rawValue)", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                        }
                    }.padding(.vertical, 10)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let meal = store.meal(on: store.planningDate, slot: slot) {
                                // A destructive swipe button removes the row before confirmation.
                                Button("Remove", systemImage: "trash") { removing = meal }
                                    .tint(.red)
                                Button("Edit", systemImage: "pencil") { selection = MealSelection(date: store.planningDate, slot: slot, meal: meal) }
                            }
                        }
                }
            } header: {
                Text(store.planningDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            } footer: {
                Text("Planning a meal doesn’t change your grocery list. Add ingredients when you’re ready to shop.")
            }
            Section {
                Menu {
                    Button("This Week", systemImage: "calendar.day.timeline.left") { reviewPeriod = .week }
                    Button("This Month", systemImage: "calendar") { reviewPeriod = .month }
                } label: {
                    Label("Review groceries", systemImage: "basket")
                }
            }
        }
        .navigationTitle("Meal Plan")
        .tabRootStyle()
        // Kept out of the List so paging between weeks doesn't compete with the list's scrolling.
        .safeAreaBar(edge: .top) {
            if !typeSize.isAccessibilitySize { WeekStrip().padding(.bottom, 6) }
        }
        .navigationSubtitle(store.planningDate.formatted(.dateTime.month(.wide).year()))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { withAnimation(reduceMotion ? nil : .default) { store.planningDate = Calendar.current.startOfDay(for: .now) } }
                    .disabled(Calendar.current.isDateInToday(store.planningDate))
                    .toolbarGlyph()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Choose a date", systemImage: "calendar") { showCalendar = true }
                    .toolbarGlyph()
                    .popover(isPresented: $showCalendar) {
                        DatePicker("Selected day", selection: Binding(
                            get: { store.planningDate },
                            set: { store.planningDate = Calendar.current.startOfDay(for: $0); showCalendar = false }
                        ), in: CalendarDays.plannableRange, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.calendar, weekStart.calendar)
                            .frame(idealWidth: 320, maxWidth: 400)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .sheet(item: $selection) { MealPickerView(selection: $0) }
        .sheet(item: $reviewPeriod) { period in
            GroceryImportReviewView(candidates: groceryCandidates(for: period))
        }
        .calendishAlert("Remove This Planned Meal?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove Meal", role: .destructive) {
                if let removing { store.removeMeal(removing) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("The recipe stays in your recipe book.") }
    }

    private func dayStatus(_ day: Date) -> String {
        WeekStrip.status(of: day, meals: store.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.count)
    }

    private func groceryCandidates(for period: GroceryReviewPeriod) -> [GroceryImportCandidate] {
        let calendar = Calendar.current
        let days = CalendarDays.week(containing: store.planningDate)
        let meals = store.meals.filter { meal in
            if period == .month { return calendar.isDate(meal.date, equalTo: store.planningDate, toGranularity: .month) }
            return days.contains { calendar.isDate($0, inSameDayAs: meal.date) }
        }
        return GroceryImportCandidate.planned(meals)

    }
}

/// A horizontally paging strip of weeks. Swiping keeps the same weekday selected.
struct WeekStrip: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var weeks: [Date] = []
    @State private var visibleWeek: Date?
    @State private var isScrolling = false

    var body: some View {
        let calendar = Calendar.current
        let mealCounts = Dictionary(store.meals.map { (calendar.startOfDay(for: $0.date), 1) }, uniquingKeysWith: +)
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = calendar.date(byAdding: .day, value: offset, to: week)!
                            dayButton(day, meals: mealCounts[day, default: 0])
                        }
                    }
                    // Inset inside each page, so neighboring weeks are separated by a clear gap mid-swipe.
                    .padding(.horizontal, 20)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleWeek)
        // A horizontal scroll view otherwise takes all the height it's offered.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { if weeks.isEmpty { loadWeeks() } }
        .onChange(of: weekStart) { _, _ in loadWeeks() }
        // Commit the new week only once the swipe settles, so the screen doesn't redraw mid-gesture.
        .onScrollPhaseChange { _, phase in
            isScrolling = phase != .idle
            guard phase == .idle, let week = visibleWeek else { return }
            let current = CalendarDays.startOfWeek(store.planningDate)
            guard week != current else { return }
            let weekday = calendar.dateComponents([.day], from: current, to: store.planningDate).day ?? 0
            store.planningDate = calendar.date(byAdding: .day, value: weekday, to: week)!
        }
        // Follow date changes made elsewhere (Today, the date picker) without fighting a swipe in progress.
        .onChange(of: store.planningDate) { _, date in
            let week = CalendarDays.startOfWeek(date)
            guard !isScrolling, visibleWeek != week else { return }
            withAnimation(reduceMotion ? nil : .default) { visibleWeek = week }
        }
    }

    private func loadWeeks() {
        weeks = CalendarDays.plannableWeeks
        visibleWeek = CalendarDays.startOfWeek(store.planningDate)
    }

    private func dayButton(_ day: Date, meals: Int) -> some View {
        let selected = Calendar.current.isDate(day, inSameDayAs: store.planningDate)
        let today = Calendar.current.isDateInToday(day)
        return Button { store.planningDate = day } label: {
            VStack(spacing: 9) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                    .foregroundStyle(selected ? CalendishStyle.onAccent.opacity(0.75) : Color.secondary)
                Text(day.formatted(.dateTime.day())).font(.headline)
                    .foregroundStyle(selected ? CalendishStyle.onAccent : (today ? CalendishStyle.accent : Color.primary))
                Circle().fill(meals > 0 ? (selected ? CalendishStyle.onAccent : CalendishStyle.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background {
                if selected {
                    // Non-interactive so the glass never claims the drag that pages between weeks.
                    Color.clear
                        .glassEffect(.regular.tint(CalendishStyle.accent), in: .rect(cornerRadius: 18))
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selected)
        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityValue(Self.status(of: day, meals: meals))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func status(of day: Date, meals count: Int) -> String {
        (Calendar.current.isDateInToday(day) ? "Today, " : "") + "\(count) \(count == 1 ? "meal" : "meals") planned"
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
    @State private var slot = MealSlot.dinner
    @State private var initialValues: String?
    @State private var discardChanges = false
    @AppStorage(MealSlot.enabledStorageKey) private var enabledSlots = MealSlot.allEnabled
    /// Turned-off slots stay available when the meal being edited already uses one.
    private var slots: [MealSlot] {
        let enabled = MealSlot.enabled(in: enabledSlots)
        return MealSlot.allCases.filter { enabled.contains($0) || $0 == selection.slot || $0 == slot }
    }
    private var values: String { "\(keepsSavedVersion)|\(recipeID?.uuidString ?? "")|\(servings)|\(date.timeIntervalSince1970)|\(slot.rawValue)" }
    private var isDirty: Bool { initialValues != nil && values != initialValues }
    /// Another meal already in the chosen day and slot, which saving will replace.
    private var replacing: Recipe? {
        guard let existing = store.meal(on: date, slot: slot), existing.id != selection.meal?.id else { return nil }
        return existing.recipe
    }
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
                        ContentUnavailableView(store.recipes.isEmpty ? "Add a Recipe First" : "No Matching Recipes", systemImage: "book.closed", description: Text(store.recipes.isEmpty ? "Open Recipes and tap Add Recipe to write your first dish." : "Try another search."))
                    }
                }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, in: CalendarDays.plannableRange, displayedComponents: .date)
                    Picker("Meal", selection: $slot) {
                        ForEach(slots) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    } currentValueLabel: {
                        Label(slot.title, systemImage: slot.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.body)
                            .imageScale(.small)
                    }
                    .pickerStyle(.menu)
                    .tint(nil)
                    ServingsField(servings: $servings)
                } footer: {
                    if let replacing { Text("This replaces \(replacing.title).") }
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
            .navigationTitle(selection.meal == nil ? "Plan a meal" : "Edit meal").navigationBarTitleDisplayMode(.inline)
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
                            store.saveMeal(date: date, slot: slot, recipe: meal.recipe, servings: servings, moving: meal, keepVersion: true)
                            dismiss()
                        } else if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
                            store.saveMeal(date: date, slot: slot, recipe: recipe, servings: servings, moving: selection.meal)
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
                slot = selection.slot
                initialValues = values
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }
}
