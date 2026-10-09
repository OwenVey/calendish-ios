import AlarmKit
import AudioToolbox
import SwiftUI
import UserNotifications
import Observation

/// Full-screen, adaptive step-by-step view for cooking a recipe.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    /// The recipe to mark as cooked on finishing, when it's in the person's recipe book.
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
    @Environment(CookingTimers.self) private var timerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var handsFree = HandsFreeCooking(speech: LocalHandsFreeSpeech())
    @State private var showHandsFreeIntro = false
    @AppStorage(PreferenceKey.handsFreeIntroSeen) private var handsFreeIntroSeen = false
    @State private var ingredientScope = IngredientScope.all
    @State private var wideLayout = false
    @State private var ingredientFocus: IngredientFocus?

    private struct IngredientFocus {
        let id = UUID()
        let ingredients: [UUID]
    }
    @AppStorage(PreferenceKey.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(PreferenceKey.cookingHaptics) private var haptics = true
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    private var timers: [CookTimer] { timerStore.timers.filter { $0.recipeID == recipe.id } }
    private var scale: Double { recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1 }
    private var isLastStep: Bool { stepIndex >= recipe.steps.count - 1 }

    private enum IngredientScope: String, CaseIterable, Identifiable {
        case all = "All Ingredients"
        case currentStep = "Current Step"
        var id: Self { self }
    }

    private var visibleIngredients: [Ingredient] {
        guard ingredientScope == .currentStep else { return recipe.ingredients }
        guard recipe.steps.indices.contains(stepIndex) else { return [] }
        let mentioned = Set(IngredientParser.mentions(in: recipe.steps[stepIndex],
            ingredients: recipe.ingredients.map(\.text)).flatMap(\.ingredients))
        return recipe.ingredients.enumerated().compactMap { mentioned.contains($0.offset) ? $0.element : nil }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 650 && (geometry.size.width > geometry.size.height || geometry.size.width >= 900)
                let sheetHeight = min(340, max(220, geometry.size.height * 0.38))
                HStack(spacing: 0) {
                    if wide && showIngredients {
                        ingredientList
                            .frame(width: min(typeSize.isAccessibilitySize ? 380 : 320, geometry.size.width * 0.4))
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
                            .padding(.leading, 16)
                            .padding(.vertical, 12)
                            .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
                    }
                    VStack(spacing: 0) {
                        TabView(selection: stepSelection) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                stepPage(step, at: index).tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .top) { finishedTimerBanner }
                        if handsFree.status != .off { handsFreeStatus }
                        stepControls
                    }
                    .padding(.bottom, !wide && showIngredients ? sheetHeight + geometry.safeAreaInsets.bottom + 12 : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: showIngredients)
                }
                .onAppear { wideLayout = wide }
                .onChange(of: wide) { _, value in wideLayout = value }
                .sheet(isPresented: Binding(
                    get: { showIngredients && !wideLayout },
                    set: { visible in
                        guard !wideLayout else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { showIngredients = visible }
                    }
                )) {
                    ingredientList
                        .calendishAlert("Timer Done", isPresented: timerAlertPresented(onIngredients: true)) {
                            Button("Done") { }
                        } message: { Text(timerFinishedMessage) }
                        .presentationDetents([.height(sheetHeight), .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(sheetHeight)))
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.resizes)
                        .presentationBackground(Color(.secondarySystemGroupedBackground))
                }
            }
            .background(CalendishStyle.background)
            .navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { session.end(); dismiss() }.toolbarGlyph()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(handsFree.keepsScreenAwake ? "Stop Voice Commands" : "Voice Commands",
                           systemImage: handsFree.keepsScreenAwake ? "mic.fill" : "mic") {
                        if handsFree.keepsScreenAwake { handsFree.stop() }
                        else if handsFreeIntroSeen { handsFree.enable() }
                        else { showHandsFreeIntro = true }
                    }
                    .toolbarGlyph()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showIngredients ? "Hide Ingredients" : "Show Ingredients", systemImage: "list.bullet") {
                        withAnimation(reduceMotion ? nil : .default) { showIngredients.toggle() }
                    }
                    .toolbarGlyph()
                }
                if let next = timers.min(by: { $0.end < $1.end }) {
                    ToolbarItem(placement: .topBarTrailing) { timerMenu(next: next) }
                }
            }
        }
        .onChange(of: stepIndex) { _, _ in ingredientFocus = nil }
        .sensoryFeedback(.selection, trigger: stepIndex) { _, _ in haptics }
        .sensoryFeedback(.success, trigger: timerStore.finished.first?.id) { _, _ in haptics }
        .calendishAlert("Timer Done", isPresented: timerAlertPresented(onIngredients: false)) {
            Button("Done") { }
        } message: { Text(timerFinishedMessage) }
        .calendishAlert("Voice Commands", isPresented: $showHandsFreeIntro) {
            Button("Cancel", role: .cancel) { }
            Button("Turn On") {
                handsFreeIntroSeen = true
                handsFree.enable()
            }
        } message: {
            Text("Say “next”, “back”, or “start timer” without touching your phone. Calendish listens only while Cook Mode is open, and speech stays on this iPhone.\n\nAnyone nearby, or a TV, saying a command can trigger it too.")
        }
        .onAppear {
            session.begin(recipe: recipe, servings: servings)
            timerStore.isCooking = true
            updateScreenAwake()
        }
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
        .onDisappear {
            handsFree.stop()
            timerStore.isCooking = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // Present timer alerts from the visible sheet when it owns the presentation.
    private func timerAlertPresented(onIngredients: Bool) -> Binding<Bool> {
        Binding(
            get: { !timerStore.finished.isEmpty && !handsFree.isListening && (showIngredients && !wideLayout) == onIngredients },
            set: { if !$0 && (showIngredients && !wideLayout) == onIngredients { timerStore.acknowledge() } }
        )
    }

    /// Hands-free use keeps the screen awake even when the usual preference is off.
    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake || handsFree.keepsScreenAwake
    }

    @ViewBuilder private var finishedTimerBanner: some View {
        if !handsFree.finishedTimers.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "timer").foregroundStyle(CalendishStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer Done").font(.headline)
                    ForEach(handsFree.finishedTimers) { timer in
                        Text("\(timer.recipeID == recipe.id ? "" : "\(timer.recipeTitle), ")Step \(timer.stepIndex + 1): your \(timer.durationText) timer is up.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss", systemImage: "xmark") {
                    withAnimation(reduceMotion ? nil : .default) { handsFree.dismissFinishedTimers() }
                }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .tint(Color.primary)
            }
            .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16).padding(.top, 8)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    private var handsFreeStatus: some View {
        HStack(spacing: 12) {
            switch handsFree.status {
            case .off: EmptyView()
            case .starting:
                ProgressView()
                statusText("Starting voice commands…")
            case .preparing(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    statusText("Preparing voice commands")
                    ProgressView(value: progress).tint(CalendishStyle.accent)
                }
                Button("Cancel") { handsFree.stop() }.modifier(GlassActionStyle())
            case .listening:
                Image(systemName: "waveform")
                    .foregroundStyle(CalendishStyle.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening").font(.subheadline.weight(.semibold))
                    Text(handsFree.outcome ?? "Say “next”, “back”, or “start timer”")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Stop") { handsFree.stop() }.modifier(GlassActionStyle())
            case .paused:
                statusText("Voice commands paused")
                Button("Resume") { handsFree.enable() }.modifier(GlassActionStyle())
                closeHandsFree
            case .failed:
                statusText("Voice commands stopped unexpectedly")
                Button("Retry") { handsFree.enable() }.modifier(GlassActionStyle())
                closeHandsFree
            case .preparationFailed:
                statusText("Couldn’t prepare voice commands")
                Button("Retry") { handsFree.enable() }.modifier(GlassActionStyle())
                closeHandsFree
            case .microphoneDenied:
                statusText("Voice commands need microphone access. You can allow it in Settings.")
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .modifier(GlassActionStyle())
                closeHandsFree
            case .unavailable(let reason):
                statusText(reason)
                closeHandsFree
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 56)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func statusText(_ text: String) -> some View {
        Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeHandsFree: some View {
        Button("Turn Off Voice Commands", systemImage: "xmark") { handsFree.stop() }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .tint(Color.primary)
    }

    private var timerFinishedMessage: String {
        timerStore.finished.map { "\($0.recipeTitle), step \($0.stepIndex + 1): your \($0.durationText) timer is up." }.joined(separator: "\n\n")
    }

    private var stepControls: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                Button {
                    withAnimation(reduceMotion ? nil : .default) { stepIndex = max(0, stepIndex - 1) }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.title2.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Previous Step")
                .tint(Color.primary)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(stepIndex == 0)
                Spacer(minLength: 0)
                Menu {
                    Picker("Step", selection: stepSelection) {
                        ForEach(recipe.steps.indices, id: \.self) { index in
                            Text("Step \(index + 1)").tag(index)
                        }
                    }
                } label: {
                    Text("Step \(stepIndex + 1) of \(recipe.steps.count)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .frame(minHeight: 44)
                }
                .tint(Color.primary)
                .accessibilityHint("Choose a step")
                Spacer(minLength: 0)
                if isLastStep {
                    Button {
                        session.end(finished: true)
                        if let cookedRecipeID { store.markCooked(cookedRecipeID) }
                        dismiss()
                    } label: { OnAccentLabel(title: "Finish", systemImage: "checkmark") }
                        .controlSize(.large)
                        .modifier(GlassActionStyle(prominent: true))
                } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .default) { stepIndex = min(recipe.steps.count - 1, stepIndex + 1) }
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(CalendishStyle.onAccent)
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Next Step")
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Picker("Ingredients", selection: $ingredientScope) {
                        ForEach(IngredientScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(ingredientScope.rawValue).font(.title2.weight(.semibold)).foregroundStyle(Color.primary)
                        Image(systemName: "chevron.down").font(.body.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44, alignment: .leading)
                }
                .tint(Color.primary)
                .accessibilityHint("Show all ingredients or only those mentioned in the current step")
                Spacer(minLength: 0)
                Button {
                    withAnimation(reduceMotion ? nil : .default) { showIngredients = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Hide Ingredients")
                .accessibilityIdentifier("cook-ingredients-close")
                .tint(Color.primary)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            // Keep the panel focused on ingredients; serving scale comes from the recipe page.
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if visibleIngredients.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ingredientScope == .currentStep ? "No ingredients mentioned" : "No ingredients listed")
                                    .font(.headline)
                                Text(ingredientScope == .currentStep ? "This step doesn’t name any ingredients. Choose All Ingredients to see the full recipe." : "Follow the recipe’s instructions to get started.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                        }
                        ForEach(visibleIngredients) { ingredient in
                            let isChecked = checked.contains(ingredient.id)
                            Button {
                                if isChecked { checked.remove(ingredient.id) } else { checked.insert(ingredient.id) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(isChecked ? CalendishStyle.accent : Color.secondary)
                                    IngredientLineText(line: ingredient.display(scale: scale, units: units), highlightsAmount: !isChecked)
                                        .strikethrough(isChecked)
                                        .foregroundStyle(isChecked ? .secondary : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.title3)
                                .padding(.vertical, 12)
                                .frame(minHeight: 52)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .background(ingredientFocus?.ingredients.contains(ingredient.id) == true ? CalendishStyle.accent.opacity(0.15) : Color.clear,
                                in: .rect(cornerRadius: 12))
                            .id(ingredient.id)
                            .accessibilityIdentifier("cook-ingredient-\(ingredient.id)")
                            .accessibilityAddTraits(ingredientFocus?.ingredients.contains(ingredient.id) == true ? .isSelected : [])
                            .accessibilityValue(isChecked ? "Checked" : "Unchecked")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .onChange(of: ingredientFocus?.id) { _, _ in scrollToIngredient(using: scroll) }
                .onChange(of: ingredientScope) { _, _ in scrollToIngredient(using: scroll) }
                .onAppear { scrollToIngredient(using: scroll) }
            }
        }
        .sensoryFeedback(.selection, trigger: checked) { _, _ in haptics }
    }

    private func scrollToIngredient(using scroll: ScrollViewProxy) {
        guard let ingredient = ingredientFocus?.ingredients.first else { return }
        withAnimation(reduceMotion ? nil : .default) { scroll.scrollTo(ingredient, anchor: .center) }
    }

    private func revealIngredients(_ ingredients: [UUID]) {
        guard !ingredients.isEmpty else { return }
        ingredientFocus = IngredientFocus(ingredients: ingredients)
        withAnimation(reduceMotion ? nil : .default) { showIngredients = true }
    }

    private func stepPage(_ step: String, at index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("STEP \(index + 1)").font(.subheadline.weight(.semibold)).tracking(1.4).foregroundStyle(CalendishStyle.accent)
                RecipeStepText(step: step, recipe: recipe, scale: scale, units: units, onIngredientTap: revealIngredients).font(.title).lineSpacing(6)
                if let warning = session.activityWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let warning = timerStore.notificationWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let duration = CookTimer.duration(in: step) {
                    if let timer = timers.first(where: { $0.stepIndex == index }) {
                        HStack(spacing: 12) {
                            Label {
                                Text(timerInterval: Date.now...max(timer.end, .now), countsDown: true).monospacedDigit()
                            } icon: { Image(systemName: "timer") }
                                .font(.title3.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                            Button("Cancel", role: .destructive) { timerStore.cancel(timer) }
                                .modifier(GlassActionStyle())
                        }
                    } else {
                        Button("Start \(CookTimer.format(duration)) timer", systemImage: "timer") {
                            timerStore.start(recipe: recipe, stepIndex: index, duration: duration)
                        }
                        .controlSize(.large).modifier(GlassActionStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, wideLayout ? 24 : 28).padding(.vertical, wideLayout ? 12 : 24)
        }
    }

    private func timerMenu(next: CookTimer) -> some View {
        Menu {
            ForEach(timers.sorted { $0.end < $1.end }) { timer in
                Section("Step \(timer.stepIndex + 1) · \(timer.durationText)") {
                    Button("Go to step", systemImage: "arrow.right") { withAnimation(reduceMotion ? nil : .default) { stepIndex = timer.stepIndex } }
                    Button("Cancel timer", systemImage: "xmark", role: .destructive) { timerStore.cancel(timer) }
                }
            }
        } label: {
            Label {
                Text(timerInterval: Date.now...max(next.end, .now), countsDown: true).monospacedDigit()
            } icon: { Image(systemName: "timer") }
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Running timers")
    }

}

struct CookTimer: Identifiable, Codable {
    let id: UUID
    let recipeID: UUID
    let recipeTitle: String
    let stepIndex: Int
    let duration: TimeInterval
    let end: Date
    /// Whether AlarmKit rings for this timer. When it does, the system alarm is the whole alert.
    var usesAlarm: Bool?
    init(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        id = UUID()
        recipeID = recipe.id
        recipeTitle = recipe.title
        self.stepIndex = stepIndex
        self.duration = duration
        end = .now.addingTimeInterval(duration)
    }
    var durationText: String { Self.format(duration) }

    static func format(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// Finds the first time like "25 minutes" or "1-2 hrs" in a step. Ranges use the shorter time.
    static func duration(in step: String) -> TimeInterval? {
        let pattern = #/(\d+)\s*(?:(?:-|–|to)\s*\d+\s*)?(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/#
        guard let match = try? pattern.ignoresCase().firstMatch(in: step), let value = Double(match.output.1) else { return nil }
        switch match.output.2.lowercased().first {
        case "h": return value * 3600
        case "m": return value * 60
        default: return value
        }
    }
}

nonisolated struct CookTimerAlarm: AlarmMetadata {}

/// End dates persist independently of cooking screens; system alarms or notifications cover background expiration.
@Observable
final class CookingTimers {
    static let shared = CookingTimers()
    private(set) var timers: [CookTimer] = []
    var finished: [CookTimer] = []
    var isCooking = false
    var notificationWarning: String?
    @ObservationIgnored private(set) var schedulingTask: Task<Void, Never>?
    private let storageKey = "activeCookingTimers"
    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode([CookTimer].self, from: data) { timers = saved }
    }
    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(timers), forKey: storageKey)
        CookingSession.shared.refresh()
    }
    func start(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        guard duration > 0 else { return }
        let timer = CookTimer(recipe: recipe, stepIndex: stepIndex, duration: duration)
        timers.append(timer); persist()
        schedulingTask = Task {
            let alert = TimerAlert.current
            if alert == .alarm, await scheduleAlarm(for: timer) { return }
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    notificationWarning = "Notifications are off. Keep Calendish open to hear your timers, or enable notifications in Settings."
                    return
                }
                notificationWarning = nil
                guard timers.contains(where: { $0.id == timer.id }), timer.end > .now else { return }
                let content = UNMutableNotificationContent()
                content.title = "Timer Done"
                content.body = "\(timer.recipeTitle), step \(timer.stepIndex + 1): your \(timer.durationText) timer is up."
                if alert != .silent { content.sound = .default }
                try await center.add(UNNotificationRequest(identifier: timer.id.uuidString, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.end.timeIntervalSinceNow), repeats: false)))
                if !timers.contains(where: { $0.id == timer.id }) { center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString]) }
            } catch { notificationWarning = "Couldn’t schedule a timer notification. Keep Calendish open for the alert." }
        }
    }
    /// Schedules a system alarm for the timer's end. Returns false, so a notification takes over,
    /// when alarms aren't allowed or scheduling fails.
    private func scheduleAlarm(for timer: CookTimer) async -> Bool {
        let manager = AlarmManager.shared
        do {
            let state = manager.authorizationState == .notDetermined ? try await manager.requestAuthorization() : manager.authorizationState
            guard state == .authorized, timers.contains(where: { $0.id == timer.id }), timer.end > .now else { return false }
            let title: LocalizedStringResource = "\(timer.recipeTitle) · Step \(timer.stepIndex + 1)"
            let alert: AlarmPresentation.Alert = if #available(iOS 26.1, *) {
                AlarmPresentation.Alert(title: title)
            } else {
                AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"))
            }
            let attributes = AlarmAttributes<CookTimerAlarm>(presentation: AlarmPresentation(alert: alert), tintColor: CalendishStyle.accent)
            _ = try await manager.schedule(id: timer.id, configuration: .alarm(schedule: .fixed(timer.end), attributes: attributes))
            guard let index = timers.firstIndex(where: { $0.id == timer.id }) else {
                try? manager.cancel(id: timer.id)
                return true
            }
            timers[index].usesAlarm = true; persist()
            notificationWarning = nil
            return true
        } catch { return false }
    }
    func acknowledge() { finished.removeAll() }
    func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }; persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
        try? AlarmManager.shared.cancel(id: timer.id)
    }
    func waitForNextTimer() async {
        guard let next = timers.min(by: { $0.end < $1.end }) else { return }
        do { try await Task.sleep(for: .seconds(max(0, next.end.timeIntervalSinceNow))) } catch { return }
        guard !Task.isCancelled else { return }
        timers.removeAll { $0.id == next.id }; persist()
        guard next.usesAlarm != true else { return }
        finished.append(next)
        if TimerAlert.current != .silent { AudioServicesPlayAlertSound(SystemSoundID(1005)) }
    }
}
