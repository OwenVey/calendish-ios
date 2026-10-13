import SwiftUI

/// Chooses a week and its days for auto planning, then shows the proposed dinners.
struct AutoPlanView: View {
    let plan: AutoPlan
    let saved: (Date) -> Void
    @Environment(HouseholdStore.self) private var store
    @State private var showsProposal = false
    @State private var confirmsDiscard = false
    @State private var confirmsReplace = false
    private var selectedCount: Int { plan.days.count(where: \.isSelected) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AutoPlanWeekPicker(plan: plan)
                }
                Section {
                    ForEach(plan.days) { day in
                        AutoPlanDayRow(day: day) { plan.toggleDay(day.date) }
                    }
                } header: {
                    Text("Days to plan")
                } footer: {
                    Text("Each selected day gets one dinner from your saved recipes. Days that already have a recipe or note keep their plans.")
                }
            }
            .navigationTitle("Auto plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close).toolbarGlyph()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: suggest) { OnAccentLabel(title: "Suggest dinners") }
                        .disabled(selectedCount == 0)
                        .modifier(GlassActionStyle(prominent: true))
                }
            }
            .navigationDestination(isPresented: $showsProposal) { AutoPlanProposalView(plan: plan, saved: { saved(plan.week) }) }
            .confirmationDialog("Replace suggested dinners?", isPresented: $confirmsReplace, titleVisibility: .visible) {
                Button("Replace dinners", role: .destructive) { propose() }
                Button("Keep my dinners") { showsProposal = true }
            } message: {
                Text("New suggestions replace the dinners you adjusted.")
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

    private func suggest() {
        if plan.needsDiscardConfirmation { confirmsReplace = true } else { propose() }
    }

    private func propose() {
        plan.propose()
        showsProposal = true
    }
}
