import SwiftUI

struct PasswordStepView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    let email: String
    @State private var creatingAccount = false
    @State private var password = ""
    @State private var revealed = false
    @State private var working = false
    @State private var sendingResetLink = false
    @State private var message: String?
    @State private var notice: String?
    @FocusState private var focused: Bool
    private var canSubmit: Bool { password.count >= (creatingAccount ? 8 : 6) && !working }

    var body: some View {
        AuthStep(title: creatingAccount ? "Create a password" : "Enter your password",
                 subtitle: creatingAccount ? "Use at least 8 characters." : nil) {
            VStack(alignment: .leading, spacing: 14) {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill").foregroundStyle(CalendishStyle.accent)
                        Text(email).lineLimit(1).truncationMode(.middle)
                        Text("Edit").foregroundStyle(CalendishStyle.accent)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.fill.tertiary, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change email, \(email)")
                AuthField {
                    HStack {
                        Group {
                            if revealed { TextField("Password", text: $password) }
                            else { SecureField("Password", text: $password) }
                        }
                        .textContentType(creatingAccount ? .newPassword : .password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                        Button(revealed ? "Hide password" : "Show password",
                               systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote).foregroundStyle(.red)
                        .transition(.opacity)
                } else if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        } action: {
            VStack(spacing: 4) {
                AuthButton(title: creatingAccount ? "Create account" : "Sign in", working: working,
                           workingTitle: sendingResetLink ? "Sending reset link" : creatingAccount ? "Creating account" : "Signing in") {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                if !creatingAccount {
                    Button("Forgot password?") {
                        Task {
                            working = true
                            sendingResetLink = true
                            defer { working = false; sendingResetLink = false }
                            do {
                                try await store.resetPassword(email: email)
                                message = nil
                                notice = "Check your email for a password reset link."
                            } catch { message = InterfaceCopy.failure(error, action: "send a password reset link", recovery: "Check your email address and try again.") }
                        }
                    }.frame(minHeight: 44).disabled(working)
                }
                Button(creatingAccount ? "Already have an account? Sign in" : "New to Calendish? Create an account") {
                    withAnimation(reduceMotion ? nil : .default) {
                        creatingAccount.toggle()
                        message = nil
                        notice = nil
                    }
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .disabled(working)
            }
        }
        .hapticFeedback(.error, trigger: message) { _, new in new != nil }
        .onAppear { focused = true }
    }

    private func submit() async {
        working = true
        defer { working = false }
        withAnimation(reduceMotion ? nil : .default) { message = nil; notice = nil }
        do {
            if creatingAccount {
                if try await !store.signUp(email: email, password: password) {
                    withAnimation(reduceMotion ? nil : .default) {
                        notice = "Check your email to confirm your account, then sign in."
                        creatingAccount = false
                    }
                }
            } else {
                try await store.signIn(email: email, password: password)
            }
        } catch {
            withAnimation(reduceMotion ? nil : .default) { message = InterfaceCopy.failure(error, action: creatingAccount ? "create an account" : "sign in", recovery: "Check your email and password, then try again.") }
        }
    }
}
