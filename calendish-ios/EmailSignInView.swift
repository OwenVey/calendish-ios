import SwiftUI

/// Email sign-in as a short flow of full-screen steps: email first, then a password.
struct EmailSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var path: [PasswordStep] = []
    @FocusState private var focused: Bool
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var isValidEmail: Bool {
        trimmedEmail.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            AuthStep(title: "What’s your email?", subtitle: "Use your email to sign in or create an account.") {
                AuthField {
                    TextField("Email address", text: $email, prompt: Text("name@example.com"))
                        .accessibilityLabel("Email address")
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($focused)
                        .onSubmit(next)
                }
            } action: {
                AuthButton(title: "Continue", working: false, action: next).disabled(!isValidEmail)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.toolbarGlyph()
                }
            }
            .navigationDestination(for: PasswordStep.self) { step in
                PasswordStepView(email: step.email)
            }
            .onAppear { focused = true }
        }
        .presentationDragIndicator(.visible)
    }

    private func next() {
        guard isValidEmail else { return }
        path = [PasswordStep(email: trimmedEmail)]
    }
}
