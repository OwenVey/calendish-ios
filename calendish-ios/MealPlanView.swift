import SwiftUI

struct MealSelection: Identifiable {
    let id = UUID()
    var date: Date
    var slot: MealSlot
    var meal: PlannedMeal?
    /// A recipe to preselect when planning from a recipe page.
    var recipeID: UUID?
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
    @State private var visibleWeek: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            Section {
                if typeSize.isAccessibilitySize {
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
                } else { weekStrip }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            Section {
                ForEach(MealSlot.allCases) { slot in
                    VStack(alignment: .leading, spacing: 16) {
                        Label(slot.title, systemImage: slot.symbol).font(.subheadline).foregroundStyle(.secondary)
                        if let meal = store.meal(on: store.planningDate, slot: slot), let recipe = store.recipe(for: meal) {
                            NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                            HStack {
                                Text("\(meal.servings) servings").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Edit") { selection = MealSelection(date: store.planningDate, slot: slot, meal: meal) }
                                    .font(.subheadline).frame(minHeight: 44).accessibilityLabel("Edit \(slot.title)")
                            }
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
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationSubtitle(store.planningDate.formatted(.dateTime.month(.wide).year()))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { withAnimation(reduceMotion ? nil : .default) { store.planningDate = Calendar.current.startOfDay(for: .now) } }
                    .disabled(Calendar.current.isDateInToday(store.planningDate))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Choose a date", systemImage: "calendar") { showCalendar = true }
                    .popover(isPresented: $showCalendar) {
                        DatePicker("Selected day", selection: Binding(
                            get: { store.planningDate },
                            set: { store.planningDate = Calendar.current.startOfDay(for: $0); showCalendar = false }
                        ), in: CalendarDays.plannableRange, displayedComponents: .date)
                            .datePickerStyle(.graphical)
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
        .confirmationDialog("Remove this planned meal?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove meal", role: .destructive) {
                if let removing { store.removeMeal(removing) }
                removing = nil
            }
        } message: { Text("The recipe stays in your recipe book.") }
    }

    /// A horizontally paging strip of weeks. Swiping keeps the same weekday selected.
    private var weekStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(CalendarDays.plannableWeeks, id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(CalendarDays.week(containing: week), id: \.self) { day in dayButton(day) }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleWeek)
        .onAppear { visibleWeek = CalendarDays.startOfWeek(store.planningDate) }
        .onChange(of: visibleWeek) { _, week in
            guard let week, week != CalendarDays.startOfWeek(store.planningDate) else { return }
            let weekday = Calendar.current.dateComponents([.day], from: CalendarDays.startOfWeek(store.planningDate), to: store.planningDate).day ?? 0
            store.planningDate = Calendar.current.date(byAdding: .day, value: weekday, to: week)!
        }
        .onChange(of: store.planningDate) { _, date in
            let week = CalendarDays.startOfWeek(date)
            if visibleWeek != week { withAnimation(reduceMotion ? nil : .default) { visibleWeek = week } }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = Calendar.current.isDate(day, inSameDayAs: store.planningDate)
        let today = Calendar.current.isDateInToday(day)
        return Button { store.planningDate = day } label: {
            VStack(spacing: 9) {
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption)
                Text(day.formatted(.dateTime.day())).font(.headline)
                    .foregroundStyle(selected ? CalendishStyle.onAccent : (today ? CalendishStyle.accent : Color.primary))
                Circle().fill(store.meals.contains { Calendar.current.isDate($0.date, inSameDayAs: day) } ? (selected ? CalendishStyle.onAccent : CalendishStyle.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(selected ? CalendishStyle.onAccent : Color.primary)
            .background(selected ? CalendishStyle.accent : Color.clear, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityValue(dayStatus(day))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayStatus(_ day: Date) -> String {
        let count = store.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.count
        return (Calendar.current.isDateInToday(day) ? "Today, " : "") + "\(count) \(count == 1 ? "meal" : "meals") planned"
    }

    private func groceryCandidates(for period: GroceryReviewPeriod) -> [GroceryImportCandidate] {
        let calendar = Calendar.current
        let days = CalendarDays.week(containing: store.planningDate)
        let meals = store.meals.filter { meal in
            if period == .month { return calendar.isDate(meal.date, equalTo: store.planningDate, toGranularity: .month) }
            return days.contains { calendar.isDate($0, inSameDayAs: meal.date) }
        }
        return store.recipes.compactMap { recipe in
            guard let servings = meals.filter({ $0.recipeID == recipe.id }).map(\.servings).max() else { return nil }
            return GroceryImportCandidate(recipe: recipe, servings: servings)
        }
    }
}

struct MealPickerView: View {
    let selection: MealSelection
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var recipeID: UUID?
    @State private var servings = 4
    @State private var date = Date.now
    @State private var slot = MealSlot.dinner
    @State private var initialValues: String?
    @State private var discardChanges = false
    private var values: String { "\(recipeID?.uuidString ?? "")|\(servings)|\(date.timeIntervalSince1970)|\(slot.rawValue)" }
    private var isDirty: Bool { initialValues != nil && values != initialValues }
    /// Another meal already in the chosen day and slot, which saving will replace.
    private var replacing: Recipe? {
        guard let existing = store.meal(on: date, slot: slot), existing.id != selection.meal?.id else { return nil }
        return store.recipe(for: existing)
    }
    private var recipes: [Recipe] { store.recipes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, in: CalendarDays.plannableRange, displayedComponents: .date)
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
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
                Section("Choose a recipe") {
                    ForEach(recipes) { recipe in
                        Button {
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
            .searchable(text: $search, prompt: "Find a recipe")
            .navigationTitle(selection.meal == nil ? "Plan a meal" : "Edit meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
                            store.saveMeal(date: date, slot: slot, recipe: recipe, servings: servings, moving: selection.meal)
                            dismiss()
                        }
                    }.disabled(recipeID == nil)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialValues == nil else { return }
                recipeID = selection.meal?.recipeID ?? selection.recipeID
                servings = selection.meal?.servings ?? store.recipes.first { $0.id == recipeID }?.servings ?? 4
                date = selection.date
                slot = selection.slot
                initialValues = values
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
        .confirmationDialog("Discard Meal Changes?", isPresented: $discardChanges, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing") { }
        }
    }
}
