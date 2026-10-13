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
        ScrollView {
            LazyVStack(spacing: 10) {
                if hasSaveOutcomes, let notice {
                    Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(CalendishStyle.surface, in: .rect(cornerRadius: 26))
                }
                ForEach(dinners) { dinner in
                    AutoPlanDinnerRow(dinner: dinner, plan: plan, choose: { choosing = dinner }, review: { reviewingRecipe = dinner.recipe },
                                      noAlternative: { noAlternativeMessage = plan.notice })
                }
                if !hasSaveOutcomes, let shortage = plan.shortageExplanation {
                    Text(shortage).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6).padding(.top, 4)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
        }
        .background(CalendishStyle.background)
        .disabled(savingProposal != nil)
        .navigationTitle("Suggested dinners").navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(subtitle(for: dinners))
        .toolbar {
            // At the bottom, so the title and the week's count fit beside Cancel and Add to plan.
            ToolbarItem(placement: .bottomBar) {
                Button {
                    if !plan.shuffle() { noAlternativeMessage = plan.notice }
                } label: {
                    // Bottom bars show a Label's icon only, so the text sits beside it explicitly.
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                        Text("Shuffle")
                    }
                }
                .accessibilityLabel("Shuffle dinners")
                .disabled(!plan.canShuffle || plan.isSaving || savingProposal != nil)
                .toolbarGlyph()
            }
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

    /// "Nov 22–28 · 2 of 7 days"
    private func subtitle(for dinners: [AutoPlan.Dinner]) -> String {
        "\(WeekHeader.title(for: plan.week)) · \(dinners.count { $0.recipe != nil }) of \(dinners.count) days"
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
