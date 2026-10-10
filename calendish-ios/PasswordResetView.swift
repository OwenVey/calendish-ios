import SwiftUI

struct PasswordResetView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password).textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
                } footer: { Text("Use at least 8 characters. Both passwords must match.") }
                if let message { Section { Text(message).foregroundStyle(.red) } }
                if working { ProgressView("Saving password…") }
            }
            .navigationTitle("Reset password").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working).toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            working = true
                            defer { working = false }
                            do { try await store.updatePassword(password); dismiss() }
                            catch { message = InterfaceCopy.failure(error, action: "save your password", recovery: "Try again. If the reset link has expired, request a new one.") }
                        }
                    } label: { OnAccentLabel(title: "Save password") }.disabled(working || password.count < 8 || confirmation != password).modifier(GlassActionStyle(prominent: true))
                }
            }
        }.interactiveDismissDisabled(working || !password.isEmpty)
    }
}
