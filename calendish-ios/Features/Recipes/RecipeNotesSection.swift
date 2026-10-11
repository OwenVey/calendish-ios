import SwiftUI

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
            SectionHeading(title: "Notes and ratings")
            RecipeCookedRow(recipeID: recipeID, stats: stats) { showHistory = true }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                RecipeRatingRow(member: store.currentMember, rating: Binding(get: { myReview?.rating }, set: {
                    store.saveReview(of: recipeID, rating: $0, note: myReview?.note ?? "")
                }))
                Button { editingNote = true } label: {
                    if let note = myReview?.note, !note.isEmpty {
                        Text(note).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    } else {
                        Label("Add note", systemImage: "square.and.pencil")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(myReview?.note.isEmpty == false ? Color.primary : CalendishStyle.accent)
                .frame(minHeight: 44)
                .accessibilityLabel(myReview?.note.isEmpty == false ? "Your note: \(myReview?.note ?? "")" : "Add note")
                .accessibilityHint(myReview?.note.isEmpty == false ? "Edits your note" : "Add a cooking note. Household members can see notes on recipes they can access.")
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
}
