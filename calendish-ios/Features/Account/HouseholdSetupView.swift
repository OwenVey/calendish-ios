import SwiftUI

/// Collects a name, then provisions the person's household without a create-or-join choice.
struct HouseholdSetupView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var memberName = ""
    @State private var working = false
    @State private var message: String?
    private var trimmedName: String { memberName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $memberName).textContentType(.givenName)
                } footer: {
                    Text("This is how you’ll appear to your household.")
                    if trimmedName.count > 80 { Text("Use 80 characters or fewer.").foregroundStyle(.red) }
                }
                if store.pendingInvite != nil {
                    Section {
                        Label("Your invitation is ready", systemImage: "person.2")
                        Text("Join the household you were invited to, or start on your own.")
                        Button("Start on my own") { store.discardPendingInvite(); message = nil }
                    }
                }
                Section {
                    Button {
                        working = true
                        message = nil
                        Task {
                            defer { working = false }
                            do { try await store.startHousehold(memberName: trimmedName) }
                            catch { message = InterfaceCopy.failure(error, action: "complete account setup", recovery: "Check your details and try again.") }
                        }
                    } label: {
                        if working { ProgressView(store.pendingInvite == nil ? "Starting household" : "Joining household") }
                        else { Text(store.pendingInvite == nil ? "Start household" : "Join household") }
                    }
                    .disabled(trimmedName.isEmpty || trimmedName.count > 80)
                } footer: { Text(store.pendingInvite == nil
                    ? "Start with your own household. Invite someone or join another household later in Settings."
                    : "Your recipes stay yours. Joining shares them with this household.") }
                if let message { Section { Text(message).foregroundStyle(.red) } }
                Section { Button("Sign out", role: .destructive) { Task { await store.signOut() } } }
            }
            .navigationTitle("Welcome")
            .disabled(working)
            .onAppear { if memberName.isEmpty { memberName = store.suggestedDisplayName } }
        }
    }
}
