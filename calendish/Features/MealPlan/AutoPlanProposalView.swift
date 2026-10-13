import SwiftUI

/// The proposed dinners, to adjust before adding them to the household's plan.
struct AutoPlanProposalView: View {
    let plan: AutoPlan
    let saved: () -> Void
    @State private var choosing: AutoPlan.Dinner?
    @State private var reviewingRecipe: Recipe?
    /// Keep the reviewed rows in place until saving ends; per-dinner outcomes must not resize them mid-save.
    @State private var savingProposal: SavingProposal?
    /// Why a swap or shuffle couldn't change anything, shown as an alert.
    @State private var noAlternativeMessage: String?

    private struct SavingProposal {
        let dinners: [AutoPlan.Dinner]
        let notice: String?
    }

    var body: some View {
        let dinners = savingProposal?.dinners ?? plan.dinners
        let notice = savingProposal == nil ? plan.notice : savingProposal?.notice
        let hasSaveOutcomes = dinners.contains { $0.outcome != nil }
        List {
            Section {
                Button("Shuffle dinners", systemImage: "shuffle") {
                    if !plan.shuffle() { noAlternativeMessage = plan.notice }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
                .disabled(!plan.canShuffle || plan.isSaving)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kept dinners stay the same.")
                    if !hasSaveOutcomes, let notice { Text(notice) }
                }
            }
            if hasSaveOutcomes, let notice {
                Section { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) }
            }
            ForEach(dinners) { dinner in
                Section {
                    AutoPlanDinnerRow(dinner: dinner, plan: plan, choose: { choosing = dinner }, review: { reviewingRecipe = dinner.recipe }, noAlternative: { noAlternativeMessage = plan.notice })
                } header: {
                    Text(dinner.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .accessibilityLabel(dinner.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
            }
        }
        .disabled(savingProposal != nil)
        .navigationTitle("Suggested dinners").navigationBarTitleDisplayMode(.inline)
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
        .navigationDestination(item: $reviewingRecipe) { RecipeDetailView(recipe: $0) }
        .sheet(item: $choosing) { dinner in AutoPlanRecipePicker(dinner: dinner, plan: plan) }
        .calendishAlert("Nothing else to suggest", isPresented: Binding { noAlternativeMessage != nil } set: { if !$0 { noAlternativeMessage = nil } },
                        presenting: noAlternativeMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { Text($0) }
    }

    private func addToPlan() async {
        guard savingProposal == nil else { return }
        savingProposal = SavingProposal(dinners: plan.dinners, notice: plan.notice)
        await plan.addToPlan()
        if plan.isFinished {
            // Retain the snapshot and spinner through dismissal, without briefly showing success rows.
            saved()
        } else {
            savingProposal = nil
        }
    }
}
