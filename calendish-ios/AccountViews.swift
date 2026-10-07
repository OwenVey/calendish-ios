import SwiftUI

struct SignInView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var working = false
    @State private var showEmail = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 22) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(CalendishStyle.onAccent)
                    .frame(width: 96, height: 96)
                    .background(CalendishStyle.accent.gradient, in: .rect(cornerRadius: 28))
                    .shadow(color: CalendishStyle.accent.opacity(0.35), radius: 24, y: 12)
                VStack(spacing: 8) {
                    Text("Calendish").font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Plan meals and shop together.").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(symbol: "book.closed", title: "One recipe book", detail: "Save the dishes you love in one place.")
                FeatureRow(symbol: "calendar", title: "A shared meal plan", detail: "Know what’s cooking every day of the week.")
                FeatureRow(symbol: "basket", title: "A live grocery list", detail: "Check things off together as you shop.")
            }
            Spacer(minLength: 40)
            VStack(spacing: 12) {
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        if working {
                            ProgressView().tint(.black)
                        } else {
                            Image("GoogleLogo").resizable().frame(width: 20, height: 20)
                            Text("Continue with Google")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: .capsule)
                    .overlay { Capsule().strokeBorder(.black.opacity(0.12)) }
                }
                .buttonStyle(.plain)
                .disabled(working)
                Button {
                    showEmail = true
                } label: {
                    Label("Continue with email", systemImage: "envelope.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .modifier(GlassActionStyle())
                .tint(CalendishStyle.accent)
                .disabled(working)
                Text(message ?? "Your household’s data stays private to its members.")
                    .font(.footnote)
                    .foregroundStyle(message == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [CalendishStyle.accent.opacity(0.22), CalendishStyle.background],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showEmail) { EmailSignInView() }
    }

    private func signInWithGoogle() async {
        message = nil
        working = true
        defer { working = false }
        do { try await store.signInWithGoogle() } catch { message = error.localizedDescription }
    }
}

/// Email sign-in as a short flow of full-screen steps: email first, then a password.
private struct EmailSignInView: View {
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
            AuthStep(title: "What’s your email?", subtitle: "We’ll sign you in, or help you create an account.") {
                AuthField {
                    TextField("name@example.com", text: $email)
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
                    Button("Close", systemImage: "xmark") { dismiss() }
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

private struct PasswordStep: Hashable { let email: String }

private struct PasswordStepView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let email: String
    @State private var creatingAccount = false
    @State private var password = ""
    @State private var revealed = false
    @State private var working = false
    @State private var message: String?
    @State private var notice: String?
    @FocusState private var focused: Bool
    private var canSubmit: Bool { password.count >= 6 && !working }

    var body: some View {
        AuthStep(title: creatingAccount ? "Create a password" : "Enter your password",
                 subtitle: creatingAccount ? "Use at least 6 characters." : nil) {
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
                AuthButton(title: creatingAccount ? "Create Account" : "Sign In", working: working) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                Button(creatingAccount ? "Already have an account? Sign in" : "New to Calendish? Create an account") {
                    withAnimation {
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
        .sensoryFeedback(.error, trigger: message) { _, new in new != nil }
        .onAppear { focused = true }
    }

    private func submit() async {
        working = true
        defer { working = false }
        withAnimation { message = nil; notice = nil }
        do {
            if creatingAccount {
                if try await !store.signUp(email: email, password: password) {
                    withAnimation {
                        notice = "Check your email to confirm your account, then sign in."
                        creatingAccount = false
                    }
                }
            } else {
                try await store.signIn(email: email, password: password)
            }
        } catch {
            withAnimation { message = error.localizedDescription }
        }
    }
}

/// One step of the email flow: a big title, its content, and a primary action pinned above the keyboard.
private struct AuthStep<Content: View, Action: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var action: Action

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.largeTitle.bold())
                    if let subtitle { Text(subtitle).font(.body).foregroundStyle(.secondary) }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.never)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            action
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A large filled text field, as used in modern onboarding flows.
private struct AuthField<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.title3)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(.fill.tertiary, in: .rect(cornerRadius: 18))
    }
}

private struct AuthButton: View {
    let title: String
    let working: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(working ? 0 : 1)
                if working { ProgressView().tint(CalendishStyle.onAccent) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .modifier(GlassActionStyle(prominent: true))
        .controlSize(.large)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(CalendishStyle.accent)
                .frame(width: 48, height: 48)
                .background(CalendishStyle.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Shown after sign-in until the account belongs to a household.
struct HouseholdSetupView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var memberName = ""
    @State private var householdName = "Our household"
    @State private var inviteCode = ""
    @State private var working = false
    @State private var message: String?
    private var trimmedName: String { memberName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $memberName).textContentType(.givenName)
                } footer: {
                    Text("This is how you’ll appear to your household.")
                }
                Section {
                    TextField("Household name", text: $householdName)
                    Button("Create Household") {
                        run { try await store.createHousehold(name: householdName.trimmingCharacters(in: .whitespaces), memberName: trimmedName) }
                    }
                    .disabled(trimmedName.isEmpty || householdName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Start a new household")
                } footer: {
                    Text("You’ll get an invite code to share with the people you cook with.")
                }
                Section {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("Join Household") {
                        run { try await store.joinHousehold(code: inviteCode, memberName: trimmedName) }
                    }
                    .disabled(trimmedName.isEmpty || inviteCode.trimmingCharacters(in: .whitespaces).count < 8)
                } header: {
                    Text("Join an existing household")
                } footer: {
                    Text("Find the code under Your household on a member’s phone.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
                Section {
                    Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
                }
            }
            .navigationTitle("Welcome")
            .disabled(working)
            .onAppear { if memberName.isEmpty { memberName = store.suggestedDisplayName } }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        message = nil
        Task {
            defer { working = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}

#Preview("Sign in") { SignInView().environment(HouseholdStore.preview()) }
