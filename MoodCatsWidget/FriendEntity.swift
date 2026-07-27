import AppIntents
import Foundation

/// One pickable person in the widget's Edit Widget sheet.
struct FriendEntity: AppEntity, Identifiable, Hashable {

    /// Profile uuid.
    var id: String
    var name: String
    /// Shown as "Kim (you)" so a widget pinned to yourself is not confusing.
    var isMe: Bool = false

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Friend"
    static let defaultQuery = FriendEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: isMe ? "\(name) (you)" : "\(name)")
    }
}

/// Populates the picker.
///
/// **Critical:** this query runs inside the widget extension process. It cannot call the
/// network and it cannot see the app's memory. Its only data source is the App Group
/// roster blob.
///
/// This is exactly why the full roster ships in every push: a new member appears in this
/// picker after the next mood change in the group, with no app launch required.
struct FriendEntityQuery: EntityQuery {

    /// Resolves identifiers already saved in a widget's configuration.
    ///
    /// A departed friend still resolves here, using their remembered name, so the widget
    /// can render "{name} left the group" instead of silently reverting to unconfigured.
    func entities(for identifiers: [FriendEntity.ID]) async throws -> [FriendEntity] {
        let roster = RosterStore.load()
        return identifiers.map { id in
            if let member = roster?.member(id: id) {
                return FriendEntity(id: id, name: member.name, isMe: id == roster?.me)
            }
            return FriendEntity(id: id, name: RosterStore.knownName(for: id) ?? "Your friend")
        }
    }

    func suggestedEntities() async throws -> [FriendEntity] {
        guard let roster = RosterStore.load() else { return [] }
        return roster.members.map {
            FriendEntity(id: $0.id, name: $0.name, isMe: $0.id == roster.me)
        }
    }

    /// Pre-selects the first friend who is not the user, so a freshly added widget shows
    /// something real instead of an empty picker.
    func defaultResult() async -> FriendEntity? {
        guard let roster = RosterStore.load() else { return nil }
        if let friend = roster.friends.first {
            return FriendEntity(id: friend.id, name: friend.name)
        }
        // A group of one: offer the user themselves rather than an empty picker.
        return (try? await suggestedEntities())?.first
    }
}
