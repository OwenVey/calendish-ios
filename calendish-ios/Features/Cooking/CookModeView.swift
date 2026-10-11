import SwiftUI

/// Full-screen, adaptive step-by-step view for cooking a recipe.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// The recipe that finishing counts toward in cooked history, when it's in the person's recipe book.
    /// A resumed session keeps the one it started with.
    var cookedRecipeID: UUID?
    /// The servings chosen on the recipe page; ingredient quantities scale to match.
    var servings: Int
    @Binding var checked: Set<UUID>
    private let session = CookingSession.shared
    private var stepIndex: Int {
        get { session.snapshot?.recipe.id == recipe.id ? session.stepIndex : 0 }
        nonmutating set { session.setStep(newValue) }
    }
    private var stepSelection: Binding<Int> {
        Binding(get: { stepIndex }, set: { stepIndex = $0 })
    }
    @State private var showIngredients = UserDefaults.standard.bool(forKey: PreferenceKey.showCookIngredients)
    /// Whether the expanded ingredient sheet was dragged to full height.
    @State private var ingredientsFullHeight = false
    /// The collapsed sheet's height: just its header, so the list can be dragged up from the bottom.
    @ScaledMetric(relativeTo: .title2) private var peekHeight: CGFloat = 68
    @Environment(CookingTimers.self) private var timerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var handsFree = HandsFreeCooking(speech: LocalHandsFreeSpeech())
    @State private var showHandsFreeIntro = false
    @AppStorage(PreferenceKey.handsFreeIntroSeen) private var handsFreeIntroSeen = false
    @State private var ingredientScope = CookIngredientScope.currentStep
    @State private var ingredientFocus: CookIngredientFocus?
    @AppStorage(PreferenceKey.keepScreenAwake) private var keepScreenAwake = true
    /// This recipe's running timers, soonest first.
    private var timers: [CookTimer] { timerStore.timers.filter { $0.recipeID == recipe.id }.sorted(by: CookTimer.soonestFirst) }
    private var scale: Double { recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1 }
    /// Ingredients sit beside the steps with room to spare (regular width) or when height is short,
    /// such as landscape iPhone; otherwise they live in a sheet that collapses instead of closing.
    private var wideLayout: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = wideLayout
                let timers = timers
                let sheetHeight = min(340, max(220, geometry.size.height * 0.38))
                let peekHeight = min(peekHeight, sheetHeight)
                HStack(spacing: 0) {
                    if wide && showIngredients {
                        ingredientPanel()
                            .frame(width: min(typeSize.isAccessibilitySize ? 380 : 320, geometry.size.width * 0.4))
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
                            .padding(.leading, 16)
                            .padding(.vertical, 12)
                            .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
                    }
                    VStack(spacing: 0) {
                        TabView(selection: stepSelection) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                CookStepPage(step: step, index: index, recipe: recipe, scale: scale, timers: timers,
                                             isWide: wide, onIngredientTap: revealIngredients)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .top) { CookFinishedTimerBanner(handsFree: handsFree, recipeID: recipe.id) }
                        if handsFree.status != .off { HandsFreeStatusBar(handsFree: handsFree) }
                        CookStepControls(stepIndex: stepSelection, stepCount: recipe.steps.count,
                                         recordsCook: session.snapshot?.cookedRecipeID != nil, onFinish: finish)
                    }
                    // The stack already ends above the bottom safe area. Counting that inset
                    // again leaves a gap above the sheet and shrinks the step's scroll area.
                    .padding(.bottom, wide ? 0 : (showIngredients ? sheetHeight : peekHeight) + 12)
                    .transaction(value: showIngredients) { transaction in
                        // Interactive sheet dismissal can suppress implicit animations.
                        // Keep the controls' layout animation independent of that transaction.
                        transaction.disablesAnimations = reduceMotion
                        transaction.animation = reduceMotion ? nil : .smooth(duration: 0.32)
                    }
                }
                .sheet(isPresented: .constant(!wideLayout)) {
                    ingredientPanel(collapsed: !showIngredients)
                        .calendishAlert("Timer finished", isPresented: timerAlertPresented(onIngredients: true)) {
                            Button("Done") { }
                        } message: { Text(timerFinishedMessage) }
                        .handsFreeIntro(isPresented: handsFreeIntroPresented(onIngredients: true), enable: enableVoiceCommands)
                        .presentationDetents([.height(peekHeight), .height(sheetHeight), .large],
                                             selection: ingredientDetent(peek: peekHeight, expanded: sheetHeight))
                        .interactiveDismissDisabled()
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(sheetHeight)))
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.resizes)
                        .presentationBackground(Color(.secondarySystemGroupedBackground))
                }
            }
            .background(CalendishStyle.background)
            .navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: close).toolbarGlyph()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(handsFree.keepsScreenAwake ? "Turn off voice commands" : "Voice commands",
                           systemImage: handsFree.keepsScreenAwake ? "mic.fill" : "mic", action: toggleVoiceCommands)
                        .modifier(ToolbarToggleStyle(isOn: handsFree.keepsScreenAwake))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showIngredients ? "Hide ingredients" : "Show ingredients", systemImage: "list.bullet", action: toggleIngredients)
                        .toolbarGlyph()
                }
            }
        }
        .onChange(of: stepIndex) { _, _ in ingredientFocus = nil }
        .hapticFeedback(.selection, trigger: stepIndex)
        .hapticFeedback(.success, trigger: timerStore.finished.first?.id)
        .calendishAlert("Timer finished", isPresented: timerAlertPresented(onIngredients: false)) {
            Button("Done") { }
        } message: { Text(timerFinishedMessage) }
        .handsFreeIntro(isPresented: handsFreeIntroPresented(onIngredients: false), enable: enableVoiceCommands)
        .onAppear(perform: beginSession)
        .onChange(of: session.snapshot?.id) { _, id in
            if id == nil { dismiss() }
        }
        .onChange(of: keepScreenAwake) { _, _ in updateScreenAwake() }
        .onChange(of: handsFree.keepsScreenAwake) { _, _ in updateScreenAwake() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { handsFree.pause() }
        }
        // While listening, finished timers are announced in a banner instead of the blocking alert.
        .onChange(of: timerStore.finished.map(\.id)) { _, _ in handsFree.announceFinishedTimers() }
        .onChange(of: handsFree.isListening) { _, _ in handsFree.announceFinishedTimers() }
        .onDisappear(perform: endSession)
    }

    // Alerts present from the ingredient sheet whenever it's up, since it covers Cook Mode.
    private func timerAlertPresented(onIngredients: Bool) -> Binding<Bool> {
        Binding(
            get: { !timerStore.finished.isEmpty && !handsFree.isListening && !wideLayout == onIngredients },
            set: { if !$0 && !wideLayout == onIngredients { timerStore.acknowledge() } }
        )
    }

    private func handsFreeIntroPresented(onIngredients: Bool) -> Binding<Bool> {
        Binding(
            get: { showHandsFreeIntro && !wideLayout == onIngredients },
            set: { if !$0 && !wideLayout == onIngredients { showHandsFreeIntro = false } }
        )
    }

    /// Maps the sheet's detents onto `showIngredients`, so the toolbar and drags agree on whether it's expanded.
    private func ingredientDetent(peek: CGFloat, expanded: CGFloat) -> Binding<PresentationDetent> {
        Binding(
            get: { !showIngredients ? .height(peek) : ingredientsFullHeight ? .large : .height(expanded) },
            set: { detent in
                ingredientsFullHeight = detent == .large
                guard showIngredients != (detent != .height(peek)) else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { showIngredients = detent != .height(peek) }
            }
        )
    }

    /// Hands-free use keeps the screen awake even when the usual preference is off.
    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake || handsFree.keepsScreenAwake
    }

    private var timerFinishedMessage: String {
        timerStore.finished.map { "\($0.recipeTitle), step \($0.stepIndex + 1): \($0.durationText) timer finished." }.joined(separator: "\n\n")
    }

    private func ingredientPanel(collapsed: Bool? = nil) -> CookIngredientPanel {
        CookIngredientPanel(recipe: recipe, stepIndex: stepIndex, scale: scale, scope: $ingredientScope,
                            checked: $checked, focus: ingredientFocus, isCollapsed: collapsed,
                            onClose: hideIngredients, onExpand: expandIngredients)
    }

    private func close() {
        session.end(keepingPlace: true)
        dismiss()
    }

    private func finish() {
        session.end(finished: true)
        dismiss()
    }

    private func toggleVoiceCommands() {
        if handsFree.keepsScreenAwake { handsFree.stop() }
        else if handsFreeIntroSeen { handsFree.enable() }
        else { showHandsFreeIntro = true }
    }

    private func enableVoiceCommands() {
        handsFreeIntroSeen = true
        handsFree.enable()
    }

    private func toggleIngredients() {
        if showIngredients { hideIngredients() } else { expandIngredients() }
    }

    private func hideIngredients() {
        ingredientsFullHeight = false
        withAnimation(reduceMotion ? nil : .default) { showIngredients = false }
    }

    private func expandIngredients() {
        withAnimation(reduceMotion ? nil : .default) { showIngredients = true }
    }

    private func revealIngredients(_ ingredients: [UUID]) {
        guard !ingredients.isEmpty else { return }
        ingredientFocus = CookIngredientFocus(ingredients: ingredients)
        expandIngredients()
    }

    private func beginSession() {
        session.begin(recipe: recipe, servings: servings, cookedRecipeID: cookedRecipeID)
        timerStore.isCooking = true
        updateScreenAwake()
    }

    private func endSession() {
        handsFree.stop()
        timerStore.isCooking = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

private extension View {
    func handsFreeIntro(isPresented: Binding<Bool>, enable: @escaping () -> Void) -> some View {
        calendishAlert("Voice commands", isPresented: isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Turn on voice commands", action: enable)
        } message: {
            Text("Say “next”, “back”, or “start timer” without touching your phone. Calendish listens only while Cook Mode is open, and speech stays on this iPhone.\n\nAnyone nearby, or a TV, saying a command can trigger it too.")
        }
    }
}
