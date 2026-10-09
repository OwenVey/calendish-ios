import SwiftUI

/// One to five stars. Tapping the current rating clears it.
struct StarRating: View {
    @Binding var rating: Int?
    var size: Font = .title2
    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .font(size)
                        .foregroundStyle(star <= (rating ?? 0) ? Color.yellow : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement()
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating.map { $0 == 1 ? "1 star" : "\($0) stars" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, (rating ?? 0) + 1)
            case .decrement: rating = (rating ?? 0) <= 1 ? nil : (rating ?? 0) - 1
            @unknown default: break
            }
        }
    }
}

/// A read-only rating, such as another member's.
struct StarsLabel: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
            }
        }
        .font(.caption)
        .accessibilityElement()
        .accessibilityLabel(rating == 1 ? "1 star" : "\(rating) stars")
    }
}

/// The recipe page's ratings, notes, and cooked history: the person's own review to edit,
/// other members' reviews to read, and when the household last cooked it.
struct RecipeNotesSection: View {
    @Environment(HouseholdStore.self) private var store
    let recipeID: UUID
    @State private var editingNote = false
    @State private var showHistory = false
    private var myReview: RecipeReview? { store.myReview(of: recipeID) }
    private var stats: RecipeStats? { store.recipeStats[recipeID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Notes & Ratings")
            cookedRow
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    MemberAvatar(member: store.currentMember, size: 28)
                    Text("You").font(.headline)
                    Spacer(minLength: 0)
                    StarRating(rating: Binding(get: { myReview?.rating }, set: {
                        store.saveReview(of: recipeID, rating: $0, note: myReview?.note ?? "")
                    }))
                }
                Button { editingNote = true } label: {
                    if let note = myReview?.note, !note.isEmpty {
                        Text(note).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    } else {
                        Label("Add a Note", systemImage: "square.and.pencil")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(myReview?.note.isEmpty == false ? Color.primary : CalendishStyle.accent)
                .frame(minHeight: 44)
                .accessibilityLabel(myReview?.note.isEmpty == false ? "Your note: \(myReview?.note ?? "")" : "Add a Note")
                .accessibilityHint(myReview?.note.isEmpty == false ? "Edits your note" : "Adds a personal tweak, like using half the salt")
            }
            ForEach(store.memberReviews(of: recipeID), id: \.member.id) { entry in
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        MemberAvatar(member: entry.member, size: 28)
                        Text(entry.member.displayName).font(.headline)
                        Spacer(minLength: 0)
                        if let rating = entry.review.rating { StarsLabel(rating: rating) }
                    }
                    if !entry.review.note.isEmpty {
                        Text(entry.review.note).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .sheet(isPresented: $editingNote) { RecipeNoteEditor(recipeID: recipeID) }
        .sheet(isPresented: $showHistory) { CookedHistoryView(recipeID: recipeID) }
    }

    private var cookedRow: some View {
        HStack(spacing: 12) {
            Button { showHistory = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CookedHistory.lastCookedText(stats?.history))
                            .foregroundStyle(.primary)
                        if let count = stats?.history.days.count, count > 0 {
                            Text(count == 1 ? "Cooked once" : "Cooked \(count) times").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows cooked history")
            if cookedToday {
                Label("Cooked Today", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button("Mark Cooked", systemImage: "checkmark") { store.markCooked(recipeID) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Mark as Cooked Today")
            }
        }
        .sensoryFeedback(.success, trigger: cookedToday) { _, cooked in cooked }
    }

    private var cookedToday: Bool { stats?.history.isMarked(on: .now) == true }
}

/// Edits the person's own note on a recipe.
private struct RecipeNoteEditor: View {
    let recipeID: UUID
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var initialText: String?
    @State private var discardChanges = false
    @FocusState private var focused: Bool
    private var isDirty: Bool { initialText != nil && text != initialText }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Use half the salt", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focused)
                } footer: {
                    Text("Your household can see your notes on recipes you share.")
                }
                if initialText?.isEmpty == false {
                    Section {
                        Button("Delete Note", role: .destructive) {
                            store.saveReview(of: recipeID, rating: store.myReview(of: recipeID)?.rating, note: "")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Your Note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard Note Changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.saveReview(of: recipeID, rating: store.myReview(of: recipeID)?.rating, note: String(text.prefix(2000)))
                        dismiss()
                    } label: { OnAccentLabel(title: "Save") }
                    .disabled(!isDirty)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialText == nil else { return }
                text = store.myReview(of: recipeID)?.note ?? ""
                initialText = text
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }
}

/// Every day the household cooked a recipe. Days marked by hand can be removed; past planned meals
/// count too and leave the history when they leave the meal plan.
private struct CookedHistoryView: View {
    let recipeID: UUID
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var day = Date.now
    private var history: CookedHistory { store.recipeStats[recipeID]?.history ?? CookedHistory() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                    Button("Mark as Cooked", systemImage: "checkmark") { store.markCooked(recipeID, on: day) }
                        .disabled(history.contains(day))
                }
                Section {
                    ForEach(history.days, id: \.date) { cooked in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cooked.date.formatted(date: .complete, time: .omitted))
                            Text(cooked.isMarked ? "Marked as cooked" : "Planned meal")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .deleteDisabled(!cooked.isMarked)
                    }
                    .onDelete { offsets in
                        let days = history.days
                        for index in offsets { store.removeCooked(recipeID, on: days[index].date) }
                    }
                    if history.days.isEmpty {
                        Text("Not cooked yet").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Days you mark and past planned meals both count. Remove a planned meal from the meal plan to take it out of the history.")
                }
            }
            .navigationTitle("Cooked History").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.toolbarGlyph()
                }
            }
        }
    }
}
