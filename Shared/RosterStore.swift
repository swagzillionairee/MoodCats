import Foundation
import os

/// The only door to App Group storage. App, widget and Notification Service Extension
/// all go through here so the monotonic write rule cannot be bypassed by accident.
public enum RosterStore {

    private static let rosterKey = "roster"
    private static let localUserKey = "me"
    private static let knownNamesKey = "knownNames"

    /// Enough history to cover a group that has churned several times over, and small
    /// enough that the blob never matters.
    private static let knownNamesLimit = 64

    private static let log = Logger(subsystem: Config.appBundleID, category: "RosterStore")

    /// `nil` only if the App Group entitlement is missing from the calling target --
    /// which is the single most common way this app breaks, so it is logged loudly.
    public static var defaults: UserDefaults? {
        guard let defaults = UserDefaults(suiteName: Config.appGroupID) else {
            log.fault("App Group \(Config.appGroupID, privacy: .public) is unavailable. Check the App Groups entitlement on THIS target.")
            return nil
        }
        return defaults
    }

    // MARK: - Read

    public static func load() -> Roster? {
        guard let data = defaults?.data(forKey: rosterKey) else { return nil }
        guard let roster = try? JSONDecoder().decode(Roster.self, from: data) else {
            log.error("Stored roster failed to decode; treating as absent.")
            return nil
        }
        guard roster.v == Roster.payloadVersion else {
            log.error("Stored roster has version \(roster.v); this build speaks \(Roster.payloadVersion).")
            return nil
        }
        return roster
    }

    /// The local user's profile id, remembered separately so a push payload -- which
    /// deliberately omits `me` -- can still be merged without losing the device's
    /// identity.
    public static var localUserID: String? {
        get { defaults?.string(forKey: localUserKey) }
        set {
            guard let defaults else { return }
            if let newValue { defaults.set(newValue, forKey: localUserKey) }
            else { defaults.removeObject(forKey: localUserKey) }
        }
    }

    // MARK: - Write

    /// Merges an incoming roster into storage.
    ///
    /// - Returns: `true` if storage changed, `false` if the payload was rejected as
    ///   stale or unreadable. Callers only reload widget timelines when this is `true`.
    ///
    /// Rejection is normal, not an error: pushes arrive out of order, and a foreground
    /// refresh routinely races a push carrying the same state.
    @discardableResult
    public static func apply(_ incoming: Roster) -> Bool {
        guard incoming.v == Roster.payloadVersion else {
            log.error("Ignoring roster with unknown version \(incoming.v).")
            return false
        }
        guard let defaults else { return false }

        let stored = load()

        // THE write rule. Strictly greater -- an equal `t` carries no new information.
        if let stored, incoming.t <= stored.t {
            log.debug("Ignoring stale roster t=\(incoming.t) (stored t=\(stored.t)).")
            return false
        }

        var next = incoming
        // A push payload has no `me`. Carry the local identity forward so the widget can
        // still tell the user apart from their friends.
        next.me = incoming.me ?? localUserID ?? stored?.me

        guard let data = try? JSONEncoder().encode(next) else {
            log.error("Failed to encode roster for storage.")
            return false
        }

        defaults.set(data, forKey: rosterKey)
        if let me = next.me { defaults.set(me, forKey: localUserKey) }
        rememberNames(in: next)

        log.debug("Stored roster t=\(next.t) with \(next.members.count) member(s).")
        return true
    }

    /// Delete My Data, and sign out. Leaves nothing behind for the widget to render.
    public static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: rosterKey)
        defaults.removeObject(forKey: localUserKey)
        defaults.removeObject(forKey: knownNamesKey)
    }

    // MARK: - Remembered names

    /// A widget pinned to someone who then leaves the group has to render
    /// "{name} left the group" -- but that person is, by definition, no longer in the
    /// roster to look their name up in. So names are remembered separately, and the
    /// widget's `EntityQuery` can still resolve a departed friend's identifier.
    private static func rememberNames(in roster: Roster) {
        guard let defaults else { return }
        var names = defaults.dictionary(forKey: knownNamesKey) as? [String: String] ?? [:]
        for member in roster.members { names[member.id] = member.n }

        if names.count > knownNamesLimit {
            // Current members always survive the trim; the overflow is old departures,
            // and which of those gets dropped does not matter.
            let current = Set(roster.members.map(\.id))
            let droppable = names.keys.filter { !current.contains($0) }
            for id in droppable.prefix(names.count - knownNamesLimit) {
                names.removeValue(forKey: id)
            }
        }

        defaults.set(names, forKey: knownNamesKey)
    }

    public static func knownName(for id: String) -> String? {
        (defaults?.dictionary(forKey: knownNamesKey) as? [String: String])?[id]
    }
}
