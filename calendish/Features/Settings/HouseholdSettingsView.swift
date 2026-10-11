import SwiftUI

struct HouseholdSettingsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var householdName = ""
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var memberToRemove: HouseholdMember?
    private enum HouseholdChange: String, Identifiable {
        case join, leave
        var id: String { rawValue }
    }
    @State private var householdChange: HouseholdChange?
    @State private var memberToOwn: HouseholdMember?
    @State private var copiedCode = false
    @State private var copiedReset: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Name") {
                TextField("Household name", text: $householdName)
                    .onSubmit { saveName() }
            }
            Section {
                ForEach(store.members) { member in
                    HStack(spacing: 12) {
                        MemberAvatar(member: member, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                            Text(member.userID == store.userID ? "You · \(member.role.capitalized)" : member.role.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isOwner, member.role != "owner" {
                            Menu {
                                Button("Make owner", systemImage: "person.badge.key") { memberToOwn = member }
                                Button("Remove member", systemImage: "person.badge.minus", role: .destructive) { memberToRemove = member }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(Color.secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Actions for \(member.displayName)")
                        }
                    }
                }
                if let code = store.household?.inviteCode {
                    Menu {
                        ShareLink(item: "Join my household on Calendish: \(HouseholdInvite.link(for: code).absoluteString)\nInvite code: \(code)") {
                            Label("Share invitation", systemImage: "square.and.arrow.up")
                        }
                        Button("Copy code", systemImage: "doc.on.doc") { copyInviteCode(code) }
                    } label: {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Text(code).font(.body.monospaced())
                                Image(systemName: copiedCode ? "checkmark" : "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: 16)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Label("Invite members", systemImage: "person.badge.plus")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityIdentifier("household-invitation")
                    .accessibilityLabel("Invite members")
                    .accessibilityValue(copiedCode ? "Code copied" : code)
                    .accessibilityHint("Share an invitation or copy the invite code")
                    .hapticFeedback(.success, trigger: copiedCode) { _, new in new }
                }
            } header: {
                Text("Members")
            } footer: {
                Text("Anyone with the code can join and edit household recipes, meal plans, and groceries.")
            }
            Section {
                Button("Join household", systemImage: "person.2.badge.plus") { householdChange = .join }
                Button("Leave household", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { householdChange = .leave }
                    // Form row icons use list-item tint separately from the button's destructive title.
                    .listItemTint(.red)
            } header: {
                Text("Change household")
            } footer: {
                Text("Your personal recipes stay with you.")
            }
            if store.isOwner {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView("Deleting household data…") }
                        else { Label("Delete household data", systemImage: "trash") }
                    }
                    .listItemTint(.red)
                    .disabled(deleting)
                } header: {
                    Text("Household data")
                } footer: {
                    Text("Deletes household-owned recipes, meal plans, and groceries. Personal recipes, members, and the invite code stay.")
                }
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household?.name ?? "" }
        .onChange(of: store.household?.id) { _, _ in householdName = store.household?.name ?? "" }
        .onDisappear { saveName() }
        .calendishAlert("Delete household data?", isPresented: $confirmDelete) {
            Button("Delete household data", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes household-owned recipes, meal plans, and groceries. Everyone’s personal recipes stay. This can’t be undone.")
        }
        .calendishAlert("Remove \(memberToRemove?.displayName ?? "Member")?", item: $memberToRemove) { member in
            Button("Remove member", role: .destructive) { store.removeMember(member) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("They keep their personal recipes and start a new household. Your household keeps separate copies of their shared recipes. Your invite code will change.")
        }
        .sheet(item: $householdChange) { change in
            HouseholdMoveView(leaving: change == .leave)
        }
        .calendishAlert("Make \(memberToOwn?.displayName ?? "this member") the owner?", item: $memberToOwn) { member in
            Button("Make owner", role: .confirm) { store.transferOwnership(to: member); memberToOwn = nil }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { memberToOwn = nil }
        } message: { member in
            Text("\(member.displayName) will manage membership. You’ll remain a member and can still edit household recipes, groceries, and meals.")
        }
        .calendishAlert("Couldn’t confirm deletion", item: $deleteError) { _ in
            Button("OK") { }
        } message: { Text($0) }
    }
    private func saveName() { store.renameHousehold(to: householdName.trimmingCharacters(in: .whitespaces)) }
    /// Copies the code and briefly confirms it with a checkmark in the invitation row.
    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedCode = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            copiedCode = false
        }
    }
    private func deleteAllData() {
        deleting = true
        Task {
            defer { deleting = false }
            do { try await store.deleteAllHouseholdData() } catch {
                await store.refresh()
                deleteError = "Check the household’s recipes, meal plan, and groceries before trying again."
            }
        }
    }
}
