import SwiftUI

struct ProfileSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var memberName = ""
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var deletingAccount = false
    @State private var deleteAccountError: String?
    private var accountDeletionExplanation: String {
        store.members.count > 1
            ? "Permanently deletes your account and personal recipes. Your household keeps the recipes you shared with it."
            : "Permanently deletes your account, personal recipes, and household, including its recipes, meal plan, and groceries."
    }
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    ProfilePhotoControl()
                    Text(store.currentMember?.displayName ?? "You").font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Your name", text: $memberName).textContentType(.givenName)
                    .onSubmit { saveName() }
            } header: {
                Text("Name")
            } footer: {
                Text("This is how you’ll appear to your household.")
            }
            if let email = store.accountEmail {
                Section("Account") {
                    LabeledContent("Email", value: email)
                }
            }
            Section {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                    .frame(maxWidth: .infinity)
                    .confirmationDialog("Sign out of Calendish?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign out", role: .destructive) { Task { await store.signOut() } }
                    }
            }
            Section {
                Button(role: .destructive) { confirmDeleteAccount = true } label: {
                    if deletingAccount { ProgressView("Deleting account…") }
                    else { Text("Delete account") }
                }
                .frame(maxWidth: .infinity)
                .disabled(deletingAccount)
            } footer: {
                Text(accountDeletionExplanation)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memberName = store.currentMember?.displayName ?? "" }
        .onDisappear { saveName() }
        .calendishAlert("Delete account?", isPresented: $confirmDeleteAccount) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(accountDeletionExplanation) This can’t be undone.")
        }
        .calendishAlert("Couldn’t confirm account deletion", item: $deleteAccountError) { _ in
            Button("OK") { }
        } message: { Text($0) }
    }
    private func saveName() { store.renameMember(to: memberName.trimmingCharacters(in: .whitespaces)) }
    private func deleteAccount() {
        deletingAccount = true
        Task {
            defer { deletingAccount = false }
            do { try await store.deleteAccount() } catch {
                deleteAccountError = "Check your account before trying again. If you can still sign in, open Profile to review your account."
            }
        }
    }
}
