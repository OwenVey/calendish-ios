import SwiftUI

/// Suggested dinners for one week's open days, started from that week's menu in the meal plan.
struct AutoPlanView: View {
    let plan: AutoPlan
    let saved: (Date) -> Void
    @Environment(HouseholdStore.self) private var store
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            AutoPlanProposalView(plan: plan, saved: { saved(plan.week) })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: close).toolbarGlyph()
                    }
                }
        }
        .confirmationDialog("Discard suggested dinners?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard dinners", role: .destructive) { store.endAutoPlan() }
            Button("Keep reviewing", role: .cancel) { }
        } message: {
            Text("Dinners you haven’t added to the plan will be lost.")
        }
        .background { DraftDismissalGuard(isDirty: plan.needsDiscardConfirmation) { confirmsDiscard = true } }
    }

    private func close() {
        if plan.needsDiscardConfirmation { confirmsDiscard = true } else { store.endAutoPlan() }
    }
}
