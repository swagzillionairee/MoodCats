import Foundation

/// Every failure the UI needs to distinguish, mapped from the stable snake_case messages
/// the database RPCs raise and the error bodies the Edge Function returns.
///
/// Keep these in sync with supabase/migrations/*_group_rpcs.sql.
enum MoodCatsError: LocalizedError, Equatable {
    case notAuthenticated
    case profileMissing
    case alreadyInGroup
    case groupNotFound
    case groupFull
    case notInAGroup
    case notOwner
    case cannotKickOwner
    case notAMember
    case invalidDisplayName
    case invalidToken
    case rateLimited(retryAfter: TimeInterval)
    case offline
    case server(String)

    /// Maps a raw error message from PostgREST or the Edge Function onto a case.
    static func from(message: String) -> MoodCatsError {
        switch message {
        case "not_authenticated", "unauthorized": .notAuthenticated
        case "profile_missing": .profileMissing
        case "already_in_group": .alreadyInGroup
        case "group_not_found": .groupNotFound
        case "group_full": .groupFull
        case "not_in_a_group": .notInAGroup
        case "not_owner": .notOwner
        case "cannot_kick_owner": .cannotKickOwner
        case "not_a_member": .notAMember
        case "invalid_display_name": .invalidDisplayName
        case "invalid_token", "invalid_environment": .invalidToken
        default: .server(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "You're signed out. Reopen MoodCats to continue."
        case .profileMissing:
            "We couldn't find your profile. Try setting your name again."
        case .alreadyInGroup:
            "You're already in a group. Leave it first to join another."
        case .groupNotFound:
            "No group with that code. Check the letters and try again."
        case .groupFull:
            "That group is full — \(Config.maxGroupMembers) people is the limit."
        case .notInAGroup:
            "You're not in a group yet."
        case .notOwner:
            "Only the person who made the group can do that."
        case .cannotKickOwner:
            "You can't remove the group's owner."
        case .notAMember:
            "That person isn't in your group anymore."
        case .invalidDisplayName:
            "Names need to be 1 to 20 characters."
        case .invalidToken:
            "This device couldn't register for notifications."
        case .rateLimited:
            "One mood at a time — try again in a moment."
        case .offline:
            "No connection. Your mood will send when you're back online."
        case .server(let message):
            "Something went wrong. (\(message))"
        }
    }
}
