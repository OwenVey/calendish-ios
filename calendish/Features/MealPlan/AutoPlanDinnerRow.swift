import SwiftUI

/// One proposed dinner with its servings, Keep, and changes, or an open day to fill by hand.
struct AutoPlanDinnerRow: View {
    let dinner: AutoPlan.Dinner
    let plan: AutoPlan
    let choose: () -> Void
    let review: () -> Void
    /// Called when an automatic alternative couldn't be found.
    let noAlternative: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showsServings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let recipe = dinner.recipe {
                Button(action: review) {
                    recipeSummary(recipe)
                }
                .buttonStyle(.plain)
                if let outcome = dinner.outcome { status(outcome) }
                if !dinner.isSettled {
                    if textSize.isAccessibilitySize {
                        servingsButton
                        HStack { keepButton; Spacer(); changeMenu }
                    } else {
                        HStack { servingsButton; Spacer(); keepButton; changeMenu }
                    }
                }
            } else {
                if textSize.isAccessibilitySize {
                    Text("Leave open").foregroundStyle(.secondary)
                    chooseButton
                } else {
                    HStack {
                        Text("Leave open").foregroundStyle(.secondary)
                        Spacer()
                        chooseButton
                    }
                }
            }
        }
    }

    private func recipeSummary(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            RecipeArtwork(recipe: recipe, compact: true, cornerRadius: 10)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline).foregroundStyle(.primary)
                    .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                    .recipeTitleAccessibility(recipe)
                if recipe.minutes > 0 {
                    Label("\(recipe.minutes) min", systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel(InterfaceCopy.minutes(recipe.minutes))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private var servingsButton: some View {
        Button(InterfaceCopy.servings(dinner.servings), systemImage: "person.2") { showsServings = true }
            .font(.subheadline).foregroundStyle(.primary).buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityHint("Adjust servings for this dinner")
            .sheet(isPresented: $showsServings) {
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
    }

    private var keepButton: some View {
        Button(dinner.isKept ? "Kept" : "Keep", systemImage: dinner.isKept ? "pin.fill" : "pin") { plan.toggleKeep(dinner.id) }
            .font(.subheadline).foregroundStyle(dinner.isKept ? CalendishStyle.accent : Color.primary)
            .buttonStyle(.borderless).frame(minHeight: 44)
            .accessibilityAddTraits(dinner.isKept ? .isSelected : [])
            .accessibilityHint(dinner.isKept ? "Allow this dinner to change when shuffling" : "Keep this dinner unchanged when shuffling")
    }

    private var changeMenu: some View {
        Menu("Change dinner", systemImage: "ellipsis.circle") {
            Button("Suggest another", systemImage: "arrow.triangle.2.circlepath") {
                if !plan.suggestAnother(for: dinner.id) { noAlternative() }
            }
            Button("Choose recipe", systemImage: "book.closed", action: choose)
            Button("Remove dinner", systemImage: "minus.circle", role: .destructive) { plan.remove(dinner.id) }
        }
        .labelStyle(.iconOnly).foregroundStyle(.primary)
        .frame(minWidth: 44, minHeight: 44)
        .menuStyle(CalendishMenuStyle()).buttonStyle(.plain)
    }

    private var chooseButton: some View {
        Button("Choose recipe", systemImage: "book.closed", action: choose)
            .font(.subheadline).buttonStyle(.borderless).frame(minHeight: 44)
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
