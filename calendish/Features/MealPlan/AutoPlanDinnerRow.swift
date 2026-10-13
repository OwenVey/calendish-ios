import SwiftUI

/// One day of a meal plan proposal: its dinner with servings and time, or an open day to fill by hand.
/// Uses the meal plan's day card and recipe row; draft changes live in the header menu.
struct AutoPlanDinnerRow: View {
    let dinner: AutoPlan.Dinner
    let plan: AutoPlan
    let choose: () -> Void
    let review: () -> Void
    /// Called when an automatic alternative couldn't be found.
    let noAlternative: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showsServings = false
    private var isEditable: Bool { dinner.recipe != nil && !dinner.isSettled }

    var body: some View {
        MealPlanDayCard(day: dinner.date, isEmphasized: true, isEmpty: dinner.recipe == nil) {
            MealPlanDayCardHeader(day: dinner.date, isEmphasized: true, isToday: Calendar.current.isDateInToday(dinner.date)) {
                Button(action: choose) {
                    Label("Choose recipe for \(weekday)", systemImage: "plus")
                        .labelStyle(.iconOnly).foregroundStyle(dinner.isSettled ? Color.secondary : Color.primary)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(dinner.isSettled)
                changeMenu.disabled(!isEditable)
            }
        } content: {
            if let recipe = dinner.recipe {
                Button(action: review) {
                    RecipeRow(recipe: recipe, servings: dinner.servings, showsOwner: false, caption: dinner.isKept ? "Kept" : nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .accessibilityHint("Shows the recipe")
                if let outcome = dinner.outcome {
                    status(outcome).font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                }
            } else {
                MealPlanDayEmptyEntry(title: "Choose recipe", action: choose)
            }
        }
        .sheet(isPresented: $showsServings) { servingsEditor }
    }

    private var weekday: String { dinner.date.formatted(.dateTime.weekday(.wide)) }

    private var changeMenu: some View {
        Menu {
            if dinner.outcome == .changed {
                Button("Use latest version", systemImage: "arrow.clockwise") { plan.useLatestVersion(for: dinner.id) }
            }
            Button("Suggest another", systemImage: "arrow.triangle.2.circlepath") {
                if !plan.suggestAnother(for: dinner.id) { noAlternative() }
            }
            Button("Choose recipe", systemImage: "book.closed", action: choose)
            Button("Servings", systemImage: "person.2") { showsServings = true }
            Button(dinner.isKept ? "Don’t keep" : "Keep when shuffling", systemImage: dinner.isKept ? "pin.slash" : "pin") {
                plan.toggleKeep(dinner.id)
            }
            Section {
                Button("Leave open", systemImage: "minus.circle", role: .destructive) { plan.remove(dinner.id) }
            }
        } label: {
            Label("Change dinner", systemImage: "ellipsis")
                .labelStyle(.iconOnly).foregroundStyle(.primary)
                .opacity(isEditable ? 1 : 0.35)
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(.plain).tint(nil)
    }

    private var servingsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Servings").font(.headline)
                Spacer()
                Button("Done") { showsServings = false }.buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Stepper(InterfaceCopy.servings(dinner.servings), value: Binding { dinner.servings } set: { plan.setServings($0, for: dinner.id) }, in: 1...1000)
        }
        .padding().frame(minWidth: 240)
        .presentationDetents([.height(textSize.isAccessibilitySize ? 260 : 180)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func status(_ outcome: AutoPlan.Outcome) -> some View {
        switch outcome {
        case .added:
            Label("Added to the plan", systemImage: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent)
        case .skipped:
            Label("Skipped. This day has plans now.", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
        case .changed:
            Label("This recipe changed. Use its latest version from the menu.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .unavailable:
            Label("This recipe isn’t available anymore. Choose another.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .failed:
            Label("Couldn’t confirm this dinner. Try again when you’re connected.", systemImage: "exclamationmark.arrow.circlepath").foregroundStyle(.orange)
        }
    }
}
