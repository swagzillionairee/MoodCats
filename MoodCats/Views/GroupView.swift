import SwiftUI
import UIKit

/// Screen 6. Everyone's cat, name and how long since they last changed it.
/// The owner gets a kick action per member plus Delete Group; everyone else gets Leave.
struct GroupView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingLeave = false
    @State private var memberToKick: RosterMember?
    @State private var didCopyCode = false

    var body: some View {
        NavigationStack {
            List {
                if let code = model.group?.code {
                    Section("Group code") {
                        HStack {
                            Text(code)
                                .font(.system(.title3, design: .monospaced).weight(.bold))
                                .kerning(3)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = code
                                didCopyCode = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    didCopyCode = false
                                }
                            } label: {
                                Label(
                                    didCopyCode ? "Copied" : "Copy",
                                    systemImage: didCopyCode ? "checkmark" : "doc.on.doc"
                                )
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    ForEach(members) { member in
                        MemberRow(
                            member: member,
                            isMe: member.id == model.myID,
                            isOwner: isOwner(member),
                            isHighlighted: member.id == model.highlightedFriendID
                        )
                        .swipeActions(edge: .trailing) {
                            if model.isOwner, !isOwner(member) {
                                Button(role: .destructive) {
                                    memberToKick = member
                                } label: {
                                    Label("Remove", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(members.count) of \(Config.maxGroupMembers)")
                } footer: {
                    if members.count == 1 {
                        Text("Share your code to get some friends in here.")
                    }
                }

                Section {
                    Button(model.isOwner ? "Delete group" : "Leave group", role: .destructive) {
                        confirmingLeave = true
                    }
                } footer: {
                    Text(model.isOwner
                         ? "Deleting removes the group for everyone. Their cats stay, the group doesn't."
                         : "You can rejoin later with the same code.")
                }
            }
            .navigationTitle("Group")
            .refreshable { await model.refresh() }
            .task { if model.group == nil { await model.loadGroup() } }
            .confirmationDialog(
                model.isOwner ? "Delete this group?" : "Leave this group?",
                isPresented: $confirmingLeave,
                titleVisibility: .visible
            ) {
                Button(model.isOwner ? "Delete group" : "Leave", role: .destructive) {
                    Task { await model.leaveGroup() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Remove \(memberToKick?.name ?? "")?",
                isPresented: Binding(
                    get: { memberToKick != nil },
                    set: { if !$0 { memberToKick = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let member = memberToKick {
                        Task { await model.kick(member) }
                    }
                    memberToKick = nil
                }
                Button("Cancel", role: .cancel) { memberToKick = nil }
            }
        }
    }

    /// Me first, then everyone else in roster order.
    ///
    /// Partitioned rather than sorted: `sorted { $0.id == myID }` is not a strict weak
    /// ordering and produces undefined results.
    private var members: [RosterMember] {
        guard let roster = model.roster else { return [] }
        guard let myID = model.myID else { return roster.members }
        return roster.members.filter { $0.id == myID } + roster.members.filter { $0.id != myID }
    }

    private func isOwner(_ member: RosterMember) -> Bool {
        model.group?.ownerId.uuidString.lowercased() == member.id.lowercased()
    }
}

private struct MemberRow: View {
    let member: RosterMember
    let isMe: Bool
    let isOwner: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            CatFaceView(mood: member.mood, size: 20)
                .foregroundStyle(.tint)
                .frame(minWidth: 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.name).font(.body.weight(.medium))
                    if isMe {
                        Text("you")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    if isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Group owner")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let mood = member.mood?.label ?? "Unknown"
        return "\(mood) · \(RelativeTime.string(from: member.updatedAt))"
    }
}
