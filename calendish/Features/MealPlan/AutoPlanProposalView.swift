import SwiftUI

/// The proposed dinners, to adjust before adding them to the household's plan.
struct AutoPlanProposalView: View {
    let plan: AutoPlan
    let close: () -> Void
    @State private var choosing: AutoPlan.Dinner?
    /// Why a swap or shuffle couldn't change anything, shown as an alert.
    @State private var noAlternativeMessage: String?

    var body: some View {
        List {
            if let notice = plan.notice {
                Section { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) }
            }
            ForEach(plan.dinners) { dinner in
                Section(dinner.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    AutoPlanDinnerRow(dinner: dinner, plan: plan, choose: { choosing = dinner }, noAlternative: { noAlternativeMessage = plan.notice })
                }
            }
        }
        .navigationTitle("Suggested dinners").navigationBarTitleDisplayMode(.inline)
        // Going back to choose days again would replace dinners already added.
        .navigationBarBackButtonHidden(plan.dinners.contains { $0.outcome != nil } || plan.isSaving)
        .toolbar {
            if !plan.isFinished {
                ToolbarItem(placement: .bottomBar) {
                    Button("Shuffle", systemImage: "shuffle") { if !plan.shuffle() { noAlternativeMessage = plan.notice } }
                        .labelStyle(.titleAndIcon)
                        .disabled(!plan.canShuffle || plan.isSaving)
                        .toolbarGlyph()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if plan.isFinished {
                    Button(action: close) { OnAccentLabel(title: "Done") }
                        .modifier(GlassActionStyle(prominent: true))
                } else if plan.isSaving {
                    ProgressView().accessibilityLabel("Adding dinners")
                } else {
                    Button { Task { await plan.addToPlan() } } label: { OnAccentLabel(title: "Add to plan") }
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
}
