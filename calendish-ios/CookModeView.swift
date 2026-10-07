import SwiftUI
import AudioToolbox

/// Full-screen, landscape step-by-step view for cooking a recipe.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @Binding var checked: Set<UUID>
    @State private var stepIndex = 0
    @State private var showIngredients = true
    @State private var timers: [CookTimer] = []
    @State private var finishedTimer: CookTimer?
    private var isLastStep: Bool { stepIndex >= recipe.steps.count - 1 }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if showIngredients {
                    ingredientList
                        .frame(width: 300)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                TabView(selection: $stepIndex) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepPage(step, at: index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(CalendishStyle.background)
            .navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(showIngredients ? "Hide ingredients" : "Show ingredients", systemImage: "sidebar.leading") {
                        withAnimation { showIngredients.toggle() }
                    }
                }
                if let next = timers.min(by: { $0.end < $1.end }) {
                    ToolbarItem(placement: .topBarTrailing) { timerMenu(next: next) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Previous step", systemImage: "chevron.backward") { withAnimation { stepIndex -= 1 } }
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
                        Button("Next step", systemImage: "chevron.forward") { withAnimation { stepIndex += 1 } }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: stepIndex)
        .sensoryFeedback(.success, trigger: finishedTimer?.id) { _, new in new != nil }
        .task(id: timers.map(\.end)) { await waitForNextTimer() }
        .alert("Timer done", isPresented: Binding(get: { finishedTimer != nil }, set: { if !$0 { finishedTimer = nil } }), presenting: finishedTimer) { _ in
            Button("OK") {}
        } message: { timer in
            Text("Your \(timer.durationText) timer for step \(timer.stepIndex + 1) is up.")
        }
        .onAppear {
            OrientationLock.lock(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            OrientationLock.unlock()
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
                            Text(ingredient.text).strikethrough(isChecked).foregroundStyle(isChecked ? .secondary : .primary)
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
                Text("\(recipe.servings) servings · \(recipe.minutes) min")
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
                if let duration = CookTimer.duration(in: step) {
                    if let timer = timers.first(where: { $0.stepIndex == index }) {
                        HStack(spacing: 12) {
                            Label {
                                Text(timerInterval: Date.now...max(timer.end, .now), countsDown: true).monospacedDigit()
                            } icon: { Image(systemName: "timer") }
                                .font(.title3.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                            Button("Cancel", role: .destructive) { timers.removeAll { $0.id == timer.id } }
                                .modifier(GlassActionStyle())
                        }
                    } else {
                        Button("Start \(CookTimer.format(duration)) timer", systemImage: "timer") {
                            timers.append(CookTimer(stepIndex: index, duration: duration))
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
                    Button("Go to step", systemImage: "arrow.right") { withAnimation { stepIndex = timer.stepIndex } }
                    Button("Cancel timer", systemImage: "xmark", role: .destructive) { timers.removeAll { $0.id == timer.id } }
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

    /// Sleeps until the soonest timer ends, then alerts. Restarts whenever timers change.
    private func waitForNextTimer() async {
        guard let next = timers.min(by: { $0.end < $1.end }) else { return }
        try? await Task.sleep(for: .seconds(max(0, next.end.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        timers.removeAll { $0.id == next.id }
        finishedTimer = next
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}

struct CookTimer: Identifiable {
    let id = UUID()
    let stepIndex: Int
    let duration: TimeInterval
    let end: Date
    init(stepIndex: Int, duration: TimeInterval) {
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
