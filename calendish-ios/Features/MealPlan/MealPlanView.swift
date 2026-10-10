import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A planned meal dragged between days. Declared in Info.plist so drags stay within Calendish.
    nonisolated static let plannedMeal = UTType(exportedAs: "owenvey.calendish-ios.planned-meal")
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
    @State private var removing: PlanRemoval?
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
            .accessibilityAction(named: "Load previous week", loadPreviousWeek)
            .background(CalendishStyle.background)
            .navigationTitle("Meal plan")
            .tabRootStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today", systemImage: "calendar.badge.clock") { scrollToToday(using: proxy) }
                        .toolbarGlyph()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Section("Add to groceries") {
                            Button("This week", systemImage: "calendar.day.timeline.left") { reviewGroceries(weeksFromNow: 0) }
                            Button("Next week", systemImage: "calendar.day.timeline.right") { reviewGroceries(weeksFromNow: 1) }
                        }
                        Section {
                            Button("Clear meal plan", systemImage: "trash", role: .destructive) {
                                removing = PlanRemoval(meals: store.meals, clearsPlan: true)
                            }
                            .disabled(store.meals.isEmpty)
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
        .navigationDestination(for: PlannedMeal.self) { RecipeDetailView(recipe: $0.recipe, plannedMeal: $0) }
        .sheet(item: $selection) { MealPickerView(selection: $0) }
        .sheet(item: $groceryReview) { GroceryImportReviewView(candidates: $0.candidates) }
        .sheet(item: $editingNote) { MealNoteEditor(note: $0) }
        .calendishAlert(removing?.title ?? "", item: $removing) { removal in
            Button(removal.buttonTitle, role: .destructive) { remove(removal) }
            Button("Cancel", role: .cancel) { }
        } message: { removal in if let message = removal.message { Text(message) } }
    }

    private func remove(_ removal: PlanRemoval) {
        store.removeMeals(removal.meals)
        removal.notes.forEach(store.removeNote)
    }

    private func scrollToToday(using proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(Calendar.current.startOfDay(for: .now), anchor: .top) }
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
