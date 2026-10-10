import SwiftUI

struct SignInView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var working = false
    @State private var showEmail = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Color.clear.frame(height: 8)
                VStack(spacing: 22) {
                    BrandIcon(size: 96)
                    VStack(spacing: 8) {
                        Text("Calendish").font(.largeTitle.bold()).fontDesign(.rounded)
                        Text("Plan meals and shop together.").font(.title3).foregroundStyle(.secondary)
                    }
                }
                Color.clear.frame(height: 8)
                VStack(alignment: .leading, spacing: 24) {
                    FeatureRow(symbol: "book.closed", title: "One recipe book", detail: "Save the dishes you love in one place.")
                    FeatureRow(symbol: "calendar", title: "A shared meal plan", detail: "Know what’s cooking every day of the week.")
                    FeatureRow(symbol: "basket", title: "A shared grocery list", detail: "Check things off together as you shop.")
                }
                Color.clear.frame(height: 8)
                VStack(spacing: 12) {
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            if working {
                                ProgressView("Signing in with Google").tint(.black)
                            } else {
                                Image("GoogleLogo").resizable().frame(width: 20, height: 20)
                                Text("Continue with Google").fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white, in: .capsule)
                        .overlay { Capsule().strokeBorder(.black.opacity(0.12)) }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    Button {
                        showEmail = true
                    } label: {
                        Text("Continue with email").fixedSize(horizontal: false, vertical: true)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .modifier(GlassActionStyle())
                    .tint(.primary)
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
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
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
        do { try await store.signInWithGoogle() } catch { message = InterfaceCopy.failure(error, action: "sign in with Google", recovery: "Try signing in again, or use email.") }
    }
}

#Preview("Sign in") { SignInView().environment(HouseholdStore.preview()) }
