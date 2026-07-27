import Foundation

/// The shared data contract (spec section 9).
///
/// One blob, written to App Group `UserDefaults` under the key `roster`, read by the
/// widget and never fetched over the network. Compiled into all three targets so there
/// is exactly one definition of this shape in the app.
///
/// ## Units
/// `t` and `at` are unix **milliseconds**, not seconds.
///
/// The database function `public.roster_for()` is the only producer of these numbers in
/// the entire system -- the `get_roster` RPC, the `set-mood` response body and the APNs
/// payload all come out of it -- so there is a single clock and a single definition.
/// Milliseconds rather than seconds because `t` is the sequence number behind the write
/// rule below; at second resolution a foreground refresh and a push landing in the same
/// second tie, and a tie is dropped.
///
/// ## Write rule, enforced everywhere
/// Only write if the incoming `t` is **greater than** the stored `t`. That single rule is
/// what makes out of order push delivery harmless. See `RosterStore.apply(_:)`.
public struct Roster: Codable, Sendable, Equatable {

    /// Payload schema version. A reader must ignore anything it does not recognise.
    /// Mirrors `PAYLOAD_VERSION` in supabase/functions/set-mood/index.ts.
    public static let payloadVersion = 1

    public var v: Int
    public var t: Int64
    public var groupId: String?

    /// The **receiving** user's id.
    ///
    /// Present in the `get_roster` RPC result and in the `set-mood` response, absent from
    /// the APNs payload -- a push is broadcast to the whole group, so shipping the
    /// sender's id here would overwrite every recipient's own identity. `RosterStore`
    /// carries the local value forward when it merges a payload that omits it.
    public var me: String?

    public var members: [RosterMember]

    public init(v: Int, t: Int64, groupId: String?, me: String?, members: [RosterMember]) {
        self.v = v
        self.t = t
        self.groupId = groupId
        self.me = me
        self.members = members
    }

    public func member(id: String) -> RosterMember? {
        members.first { $0.id == id }
    }

    /// Everyone except the local user. What the widget picker offers.
    public var friends: [RosterMember] {
        guard let me else { return members }
        return members.filter { $0.id != me }
    }

    public var isEmpty: Bool { members.isEmpty }
}

/// One person. Keys are deliberately short: at 8 members the payload lands around
/// 400 bytes against a 4 KB APNs hard limit.
public struct RosterMember: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// Profile uuid.
    public let id: String
    /// Display name.
    public let n: String
    /// Mood id.
    public let m: Int
    /// That member's `mood_updated_at`, unix milliseconds.
    public let at: Int64

    public init(id: String, n: String, m: Int, at: Int64) {
        self.id = id
        self.n = n
        self.m = m
        self.at = at
    }

    public var name: String { n }

    /// `nil` when the id came from a newer build than this one. Callers render the
    /// neutral cat rather than guessing.
    public var mood: Mood? { Mood.known(m) }

    public var moodFace: String { Mood.face(for: mood) }

    public var updatedAt: Date { Date(timeIntervalSince1970: Double(at) / 1000) }
}

// MARK: - Push payload decoding

extension Roster {

    /// Builds a roster from an APNs `userInfo` dictionary.
    ///
    /// Returns `nil` for an unknown payload version or a shape that does not decode --
    /// the Notification Service Extension treats that as "deliver unmodified".
    public static func fromPushPayload(_ userInfo: [AnyHashable: Any]) -> Roster? {
        guard let version = userInfo["v"] as? Int, version == Roster.payloadVersion else {
            return nil
        }

        // Strip `aps`; everything else is the roster. Keys are already JSON-derived
        // types (NSString / NSNumber / NSArray), so this round trip is cheap and safe.
        var json: [String: Any] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String, key != "aps" else { continue }
            json[key] = value
        }

        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json),
              let roster = try? JSONDecoder().decode(Roster.self, from: data)
        else { return nil }

        return roster
    }
}
