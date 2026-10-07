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
    @State private var showIngredientSheet = false
    @State private var wideLayout = false
    private var timers: [CookTimer] { timerStore.timers.filter { $0.recipeID == recipe.id } }
    private var scale: Double { recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1 }
    private var isLastStep: Bool { stepIndex >= recipe.steps.count - 1 }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !typeSize.isAccessibilitySize
            HStack(spacing: 0) {
                if wide && showIngredients {
                    ingredientList
                        .frame(width: min(340, geometry.size.width * 0.35))
                        .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
                }
                TabView(selection: $stepIndex) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepPage(step, at: index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .onAppear { wideLayout = wide }
            .onChange(of: wide) { _, value in wideLayout = value }
            }
            .background(CalendishStyle.background)
            .navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(wideLayout && showIngredients ? "Hide Ingredients" : "Show Ingredients", systemImage: "list.bullet") {
                        if wideLayout { withAnimation(reduceMotion ? nil : .default) { showIngredients.toggle() } } else { showIngredientSheet = true }
                    }
                }
                if let next = timers.min(by: { $0.end < $1.end }) {
                    ToolbarItem(placement: .topBarTrailing) { timerMenu(next: next) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Previous step", systemImage: "chevron.backward") { withAnimation(reduceMotion ? nil : .default) { stepIndex -= 1 } }
                        .disabled(stepIndex == 0)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Text("Step \(stepIndex + 1) of \(recipe.steps.count)").monospacedDigit().padding(.horizontal, 12)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                if isLastStep {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Finish", systemImage: "checkmark") { dismiss() }.modifier(GlassActionStyle(prominent: true))
                    }
                } else {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Next step", systemImage: "chevron.forward") { withAnimation(reduceMotion ? nil : .default) { stepIndex += 1 } }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: stepIndex)
        .sensoryFeedback(.success, trigger: timerStore.finished.first?.id)
        .alert("Timer Done", isPresented: Binding(get: { !timerStore.finished.isEmpty }, set: { if !$0 { timerStore.acknowledge() } })) {
            Button("Done") { }
        } message: {
            Text(timerStore.finished.map { "\($0.recipeTitle), step \($0.stepIndex + 1): your \($0.durationText) timer is up." }.joined(separator: "\n\n"))
        }
        .sheet(isPresented: $showIngredientSheet) {
            NavigationStack {
                ingredientList.navigationTitle("Ingredients")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIngredientSheet = false } } }
            }
            .presentationBackground(Color(.systemGroupedBackground))
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            timerStore.isCooking = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            timerStore.isCooking = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var ingredientList: some View {
        List {
            Section {
                ForEach(recipe.ingredients) { ingredient in
                    let isChecked = checked.contains(ingredient.id)
                    Button {
                        if isChecked { checked.remove(ingredient.id) } else { checked.insert(ingredient.id) }
                    } label: {
                        Label {
                            Text(ingredient.scaled(by: scale)).strikethrough(isChecked).foregroundStyle(isChecked ? .secondary : .primary)
                        } icon: {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChecked ? CalendishStyle.accent : Color.secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityValue(isChecked ? "Checked" : "Unchecked")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("\(servings) servings · \(recipe.minutes) min")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sensoryFeedback(.selection, trigger: checked)
    }

    private func stepPage(_ step: String, at index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("STEP \(index + 1)").font(.subheadline.weight(.semibold)).tracking(1.4).foregroundStyle(CalendishStyle.accent)
                Text(step).font(.title).lineSpacing(6)
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
            .padding(.horizontal, 32).padding(.vertical, 24)
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
                content.sound = .default
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
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}
