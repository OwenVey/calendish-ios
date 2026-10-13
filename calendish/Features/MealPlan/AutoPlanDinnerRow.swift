import SwiftUI

/// One proposed dinner with its servings, Keep, and changes, or an open day to fill by hand.
struct AutoPlanDinnerRow: View {
    let dinner: AutoPlan.Dinner
    let plan: AutoPlan
    let stats: RecipeStats?
    let choose: () -> Void
    /// Called when an automatic alternative couldn't be found.
    let noAlternative: () -> Void

    var body: some View {
        if let recipe = dinner.recipe {
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                RecipeRow(recipe: recipe, stats: stats)
            }
            if let outcome = dinner.outcome { status(outcome) }
            if !dinner.isSettled {
                Stepper(value: Binding { dinner.servings } set: { plan.setServings($0, for: dinner.id) }, in: 1...1000) {
                    Text(InterfaceCopy.servings(dinner.servings))
                }
                Toggle(isOn: Binding { dinner.isKept } set: { _ in plan.toggleKeep(dinner.id) }) {
                    Label("Keep when shuffling", systemImage: "pin").foregroundStyle(.primary)
                }
                Menu {
                    Button("Suggest another", systemImage: "arrow.triangle.2.circlepath") {
                        if !plan.suggestAnother(for: dinner.id) { noAlternative() }
                    }
                    Button("Choose recipe", systemImage: "book.closed", action: choose)
                    Button("Remove dinner", systemImage: "minus.circle", role: .destructive) { plan.remove(dinner.id) }
                } label: {
                    Label("Change dinner", systemImage: "ellipsis.circle")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .menuStyle(CalendishMenuStyle())
                .buttonStyle(.plain)
            }
        } else {
            Text(dinner.isRemoved ? "Removed. This day stays open." : "No recipe could be suggested. This day stays open.")
                .foregroundStyle(.secondary)
            Button("Choose recipe", systemImage: "book.closed", action: choose)
        }
    }

    @ViewBuilder
    private func status(_ outcome: AutoPlan.Outcome) -> some View {
        switch outcome {
        case .added:
            Label("Added to the plan", systemImage: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent)
        case .skipped:
            Label("Skipped. This day has plans now.", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
        case .changed:
            VStack(alignment: .leading, spacing: 8) {
                Label("This recipe changed since it was suggested.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Use latest version") { plan.useLatestVersion(for: dinner.id) }
            }
        case .unavailable:
            Label("This recipe isn’t available anymore. Choose another.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .failed:
            Label("Couldn’t confirm this dinner. Try again when you’re connected.", systemImage: "exclamationmark.arrow.circlepath").foregroundStyle(.orange)
        }
    }
}
