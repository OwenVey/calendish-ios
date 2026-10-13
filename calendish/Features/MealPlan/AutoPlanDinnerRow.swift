import SwiftUI

/// One day of a meal plan proposal: its dinner with servings and time, or an open day to fill by hand.
/// Changes, servings, and Keep live in the row's menu and swipe actions.
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
        HStack(spacing: 12) {
            Button(action: dinner.recipe == nil ? choose : review) {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        dayLabel
                        if let recipe = dinner.recipe {
                            Text(recipe.title).font(.headline).foregroundStyle(.primary)
                                .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                            Text(details(for: recipe)).font(.subheadline).foregroundStyle(.secondary)
                            if let outcome = dinner.outcome { status(outcome).font(.subheadline) }
                        } else {
                            Text("No dinner").font(.headline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(dinner.recipe == nil ? "Choose a recipe" : "Shows the recipe")
            if isEditable { changeMenu }
        }
        .swipeActions(edge: .leading) {
            if isEditable {
                Button(dinner.isKept ? "Don’t keep" : "Keep", systemImage: dinner.isKept ? "pin.slash" : "pin") { plan.toggleKeep(dinner.id) }
                    .tint(.gray)
            }
        }
        .swipeActions(edge: .trailing) {
            if isEditable {
                Button("Leave open", systemImage: "minus.circle", role: .destructive) { plan.remove(dinner.id) }
            }
        }
        .sheet(isPresented: $showsServings) { servingsEditor }
    }

    private var dayLabel: some View {
        Text("\(Text(dinner.date.formatted(.dateTime.weekday(.wide))).foregroundStyle(.primary)) \(dinner.date.formatted(.dateTime.month(.abbreviated).day()))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var artwork: some View {
        if let recipe = dinner.recipe {
            RecipeArtwork(recipe: recipe, compact: true, thumbnail: true, cornerRadius: 10)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 52, height: 52)
                .overlay { Image(systemName: "plus").foregroundStyle(.secondary) }
                .accessibilityHidden(true)
        }
    }

    /// "4 servings · 25 min · Kept"
    private func details(for recipe: Recipe) -> String {
        var parts = [InterfaceCopy.servings(dinner.servings)]
        if recipe.minutes > 0 { parts.append("\(recipe.minutes) min") }
        if dinner.isKept { parts.append("Kept") }
        return parts.joined(separator: " · ")
    }

    private var changeMenu: some View {
        Menu("Change dinner", systemImage: "ellipsis.circle") {
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
        }
        .labelStyle(.iconOnly).foregroundStyle(.primary)
        .frame(minWidth: 44, minHeight: 44)
        .menuStyle(CalendishMenuStyle()).buttonStyle(.plain)
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
