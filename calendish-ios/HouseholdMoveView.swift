import SwiftUI

/// Reads consequences from the server before confirming an atomic household move.
struct HouseholdMoveView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var code: String? = nil
    var leaving = false
    @State private var enteredCode = ""
    @State private var preview: HouseholdMovePreview?
    @State private var saveRecipes = false
    @State private var working = false
    @State private var confirming = false
    @State private var message: String?

    private var normalizedCode: String { HouseholdInvite.normalized(code ?? enteredCode) }

    var body: some View {
        NavigationStack {
            Form {
                if !leaving && preview == nil {
                    Section {
                        TextField("Invite code", text: $enteredCode)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Review household") { Task { await loadPreview() } }
                            .disabled(normalizedCode.isEmpty || working)
                    } footer: { Text("Review the household and changes before joining. Nothing changes until you confirm.") }
                }
                if leaving && preview == nil && !working {
                    Button("Review changes") { Task { await loadPreview() } }
                }
                if let preview {
                    Section(leaving ? "Your new household" : "Household to join") {
                        Text(preview.destination?.name ?? "Your own household").font(.headline)
                        if let destination = preview.destination {
                            Text(destination.members.formatted()).foregroundStyle(.secondary)
                        } else {
                            Text("A new household for you, with an empty grocery list and meal plan.")
                        }
                    }
                    if preview.isCurrent {
                        Section {
                            Text("You already belong to this household.")
                            Button("Open household") { dismiss() }
                        }
                    } else {
                        Section("What follows you") {
                            Text("Your personal recipes stay in your collection.")
                            if !leaving { Text("Joining shares all your existing personal recipes with this household. You can make individual recipes private afterward.") }
                        }
                        Section("What stays behind") {
                            Text("Groceries and planned meals stay with \(preview.currentHouseholdName ?? "your current household").")
                            Text("Your household keeps separate copies of your shared recipes. Future edits to your personal recipes won’t change those copies.")
                        }
                        if preview.householdRecipes > 0 {
                            Section {
                                Toggle("Save household recipes to my collection", isOn: $saveRecipes)
                            } footer: { Text("Saves \(preview.householdRecipes == 1 ? "1 recipe" : "\(preview.householdRecipes) recipes") owned by the household as private copies. Recipes owned by other members aren’t included.") }
                        }
                        if let successor = preview.successor {
                            Section("Ownership") { Text("\(successor.displayName) will become the owner of your former household.") }
                        }
                        if preview.deletesHousehold {
                            Section("Empty household") {
                                Text("You are the last member. Your former household, its groceries, planned meals, and household-owned recipes will be permanently deleted. Your personal collection stays.")
                            }
                        }
                        Section {
                            Button(leaving ? "Leave household" : "Join household", role: leaving ? .destructive : nil) {
                                Task { await confirm(preview) }
                            }
                            .disabled(working)
                        }
                    }
                }
                if working { ProgressView(confirming ? "Changing household…" : "Reviewing household…") }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(leaving ? "Leave household" : "Join household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
            }
            .task {
                enteredCode = code ?? ""
                if leaving || code != nil { await loadPreview() }
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func loadPreview() async {
        working = true
        message = nil
        defer { working = false }
        do { preview = try await store.previewMove(code: leaving ? nil : normalizedCode) }
        catch { message = InterfaceCopy.failure(error, action: "review the household", recovery: leaving ? "Try reviewing the changes again." : "Check the invite code or ask a household member for a new invitation.") }
    }

    private func confirm(_ preview: HouseholdMovePreview) async {
        working = true
        confirming = true
        message = nil
        defer { working = false; confirming = false }
        do {
            if leaving { try await store.leaveHousehold(confirmed: preview, saveHouseholdRecipes: saveRecipes) }
            else { try await store.joinHousehold(code: normalizedCode, confirmed: preview, saveHouseholdRecipes: saveRecipes) }
            dismiss()
        } catch {
            message = InterfaceCopy.failure(error, action: "confirm the household change", recovery: "Check your household membership and review the changes before trying again.")
            // A rejected move may mean membership changed on another device. Require a fresh review.
            self.preview = nil
        }
    }
}
