import SwiftUI

/// The proposed dinners, to adjust before adding them to the household's plan.
struct AutoPlanProposalView: View {
    let plan: AutoPlan
    let saved: () -> Void
    @Environment(HouseholdStore.self) private var store
    @State private var choosing: AutoPlan.Dinner?
    /// Keep the reviewed rows in place until saving ends; per-dinner outcomes must not resize them mid-save.
    @State private var savingProposal: SavingProposal?
    /// Why a swap or shuffle couldn't change anything, shown as an alert.
    @State private var noAlternativeMessage: String?

    private struct SavingProposal {
        let dinners: [AutoPlan.Dinner]
        let notice: String?
        let stats: [UUID: RecipeStats]
    }

    var body: some View {
        let dinners = savingProposal?.dinners ?? plan.dinners
        let notice = savingProposal == nil ? plan.notice : savingProposal?.notice
        let stats = savingProposal?.stats ?? store.recipeStats
        List {
            Section {
                Button("Shuffle dinners", systemImage: "shuffle") {
                    if !plan.shuffle() { noAlternativeMessage = plan.notice }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
                .disabled(!plan.canShuffle || plan.isSaving)
            } footer: {
                Text("Shuffle suggests new recipes. Turn on Keep for dinners you don’t want to change.")
            }
            if let notice {
                Section { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) }
            }
            ForEach(dinners) { dinner in
                Section(dinner.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    AutoPlanDinnerRow(dinner: dinner, plan: plan, stats: dinner.recipe.flatMap { stats[$0.id] }, choose: { choosing = dinner }, noAlternative: { noAlternativeMessage = plan.notice })
                }
            }
        }
        .disabled(savingProposal != nil)
        .navigationTitle("Suggested dinners").navigationBarTitleDisplayMode(.inline)
        // Going back to choose days again would replace dinners already added.
        .navigationBarBackButtonHidden(plan.dinners.contains { $0.outcome != nil } || plan.isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if savingProposal != nil || plan.isSaving {
                    ProgressView().accessibilityLabel("Adding dinners")
                } else {
                    Button { Task { await addToPlan() } } label: { OnAccentLabel(title: "Add to plan") }
                        .disabled(!plan.canAddToPlan)
                        .modifier(GlassActionStyle(prominent: true))
                }
            }
        }
        .sheet(item: $choosing) { dinner in AutoPlanRecipePicker(dinner: dinner, plan: plan) }
        .calendishAlert("Nothing else to suggest", isPresented: Binding { noAlternativeMessage != nil } set: { if !$0 { noAlternativeMessage = nil } },
                        presenting: noAlternativeMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { Text($0) }
    }

    private func addToPlan() async {
        guard savingProposal == nil else { return }
        savingProposal = SavingProposal(dinners: plan.dinners, notice: plan.notice, stats: store.recipeStats)
        await plan.addToPlan()
        if plan.isFinished {
            // Retain the snapshot and spinner through dismissal, without briefly showing success rows.
            saved()
        } else {
            savingProposal = nil
        }
    }
}
