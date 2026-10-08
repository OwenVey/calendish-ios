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
    @State private var message: String?

    private var normalizedCode: String { HouseholdInvite.normalized(code ?? enteredCode) }

    var body: some View {
        NavigationStack {
            Form {
                if !leaving && preview == nil {
                    Section {
                        TextField("Invite code", text: $enteredCode)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Review Household") { Task { await loadPreview() } }
                            .disabled(normalizedCode.isEmpty || working)
                    } footer: { Text("Review the destination and consequences before joining. Nothing changes until you confirm.") }
                }
                if leaving && preview == nil && !working {
                    Button("Review Leave") { Task { await loadPreview() } }
                }
                if let preview {
                    Section(leaving ? "Your new household" : "Destination") {
                        Text(preview.destination?.name ?? "Your own household").font(.headline)
                        if let destination = preview.destination {
                            Text(destination.members.joined(separator: ", ")).foregroundStyle(.secondary)
                        } else {
                            Text("A fresh solo household with an empty grocery list and meal plan.")
                        }
                    }
                    if preview.isCurrent {
                        Section {
                            Text("You already belong to this household.")
                            Button("Open Household") { dismiss() }
                        }
                    } else {
                        Section("What follows you") {
                            Text("Your personal recipes stay in your collection.")
                            if !leaving { Text("Your existing personal recipes become shared with the destination household. You can set individual recipes to Only me afterward.") }
                        }
                        Section("What stays behind") {
                            Text("Groceries and planned meals stay with \(preview.currentHouseholdName ?? "your current household").")
                            Text("Your shared recipes leave independent household copies. Future edits to your personal recipes won’t change those copies.")
                        }
                        if preview.householdRecipes > 0 {
                            Section {
                                Toggle("Save household recipes to my collection", isOn: $saveRecipes)
                            } footer: { Text("Saves \(preview.householdRecipes) household-owned recipes as private personal copies before moving. Other members’ personal originals aren’t included.") }
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
                            Button(leaving ? "Leave Household" : "Join Household", role: leaving ? .destructive : nil) {
                                Task { await confirm(preview) }
                            }
                            .disabled(working)
                        }
                    }
                }
                if working { ProgressView("Working…") }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(leaving ? "Leave Household" : "Join Household")
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
        catch { message = error.localizedDescription }
    }

    private func confirm(_ preview: HouseholdMovePreview) async {
        working = true
        message = nil
        defer { working = false }
        do {
            if leaving { try await store.leaveHousehold(confirmed: preview, saveHouseholdRecipes: saveRecipes) }
            else { try await store.joinHousehold(code: normalizedCode, confirmed: preview, saveHouseholdRecipes: saveRecipes) }
            dismiss()
        } catch {
            message = error.localizedDescription
            // A rejected move may mean membership changed on another device. Require a fresh review.
            self.preview = nil
        }
    }
}
