import SwiftUI
import AudioToolbox
import UserNotifications
import Observation

/// Full-screen, adaptive step-by-step view for cooking a recipe.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// The servings chosen on the recipe page; ingredient quantities scale to match.
    var servings: Int
    @Binding var checked: Set<UUID>
    @State private var stepIndex = 0
    @State private var showIngredients = true
    @Environment(CookingTimers.self) private var timerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        TabView(selection: $stepIndex) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                stepPage(step, at: index).tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
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
                        .alert("Timer Done", isPresented: timerAlertPresented(onIngredients: true)) {
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
                    Button(role: .close) { dismiss() }.toolbarGlyph()
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
        .alert("Timer Done", isPresented: timerAlertPresented(onIngredients: false)) {
            Button("Done") { }
        } message: { Text(timerFinishedMessage) }
        .onAppear {
            timerStore.isCooking = true
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onChange(of: keepScreenAwake) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
        .onDisappear {
            timerStore.isCooking = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // Present timer alerts from the visible sheet when it owns the presentation.
    private func timerAlertPresented(onIngredients: Bool) -> Binding<Bool> {
        Binding(
            get: { !timerStore.finished.isEmpty && (showIngredients && !wideLayout) == onIngredients },
            set: { if !$0 && (showIngredients && !wideLayout) == onIngredients { timerStore.acknowledge() } }
        )
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
                    Picker("Step", selection: $stepIndex) {
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
                    Button { dismiss() } label: { OnAccentLabel(title: "Finish", systemImage: "checkmark") }
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

/// End dates persist independently of cooking screens; notifications cover background expiration.
@Observable
final class CookingTimers {
    private(set) var timers: [CookTimer] = []
    var finished: [CookTimer] = []
    var isCooking = false
    var notificationWarning: String?
    private let storageKey = "activeCookingTimers"
    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode([CookTimer].self, from: data) { timers = saved }
    }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(timers), forKey: storageKey) }
    func start(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        guard duration > 0 else { return }
        let timer = CookTimer(recipe: recipe, stepIndex: stepIndex, duration: duration)
        timers.append(timer); persist()
        Task {
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
                if UserDefaults.standard.bool(forKey: PreferenceKey.timerSound) { content.sound = .default }
                try await center.add(UNNotificationRequest(identifier: timer.id.uuidString, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.end.timeIntervalSinceNow), repeats: false)))
                if !timers.contains(where: { $0.id == timer.id }) { center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString]) }
            } catch { notificationWarning = "Couldn’t schedule a timer notification. Keep Calendish open for the alert." }
        }
    }
    func acknowledge() { finished.removeAll() }
    func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }; persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    }
    func waitForNextTimer() async {
        guard let next = timers.min(by: { $0.end < $1.end }) else { return }
        do { try await Task.sleep(for: .seconds(max(0, next.end.timeIntervalSinceNow))) } catch { return }
        guard !Task.isCancelled else { return }
        timers.removeAll { $0.id == next.id }; persist()
        finished.append(next)
        if UserDefaults.standard.bool(forKey: PreferenceKey.timerSound) { AudioServicesPlayAlertSound(SystemSoundID(1005)) }
    }
}
