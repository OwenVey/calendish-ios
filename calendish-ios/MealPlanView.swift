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
    @State private var selection: MealSelection?
    @State private var reviewPeriod: GroceryReviewPeriod?
    @State private var removing: PlannedMeal?
    @State private var showCalendar = false
    @State private var visibleWeek: Date?

    var body: some View {
        List {
            Section {
                weekStrip
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            Section {
                ForEach(MealSlot.allCases) { slot in
                    VStack(alignment: .leading, spacing: 16) {
                        Label(slot.title, systemImage: slot.symbol).font(.subheadline).foregroundStyle(.secondary)
                        if let meal = store.meal(on: store.planningDate, slot: slot), let recipe = store.recipe(for: meal) {
                            NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                            HStack {
                                Text("Planned for \(meal.servings)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Edit") { selection = MealSelection(date: store.planningDate, slot: slot, meal: meal) }
                                    .font(.subheadline)
                            }
                        } else {
                            Button {
                                selection = MealSelection(date: store.planningDate, slot: slot)
                            } label: {
                                Label("Plan \(slot.rawValue)", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                        }
                    }.padding(.vertical, 10)
                        .swipeActions {
                            if let meal = store.meal(on: store.planningDate, slot: slot) {
                                Button("Remove", role: .destructive) { removing = meal }
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
                Button("Today") { withAnimation { store.planningDate = Calendar.current.startOfDay(for: .now) } }
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
                            .frame(width: 320)
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
            if visibleWeek != week { withAnimation { visibleWeek = week } }
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
            .accessibilityAddTraits(selected ? .isSelected : [])
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
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var recipeID: UUID?
    @State private var servings = 4
    @State private var date = Date.now
    @State private var slot = MealSlot.dinner
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
                    Stepper("Servings: \(servings)", value: $servings, in: 1...1000)
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
                                if recipeID == recipe.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a recipe")
            .navigationTitle(selection.meal == nil ? "Plan a meal" : "Edit meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
                            store.saveMeal(date: date, slot: slot, recipe: recipe, servings: servings, moving: selection.meal)
                            dismiss()
                        }
                    }.disabled(recipeID == nil)
                }
            }
            .onAppear {
                recipeID = selection.meal?.recipeID ?? selection.recipeID
                servings = selection.meal?.servings ?? store.recipes.first { $0.id == recipeID }?.servings ?? 4
                date = selection.date
                slot = selection.slot
            }
        }
    }
}
