import Foundation
import OSLog
import Supabase

struct ProfileRow: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let groupId: UUID?
    let moodId: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case groupId = "group_id"
        case moodId = "mood_id"
    }
}

struct GroupRow: Decodable, Sendable {
    let id: UUID
    let code: String
    let ownerId: UUID

    enum CodingKeys: String, CodingKey {
        case id, code
        case ownerId = "owner_id"
    }
}

/// The single network boundary for the app.
///
/// Nothing else in the app talks to Supabase, and neither the widget nor the Notification
/// Service Extension links this file at all -- the widget must never make a network
/// request, and the NSE gets its data handed to it in the push payload.
final class SupabaseService {

    static let shared = SupabaseService()

    let client: SupabaseClient
    private let session: URLSession
    private let log = Logger(subsystem: Config.appBundleID, category: "Supabase")

    private init() {
        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey
        )

        let configuration = URLSessionConfiguration.default
        // A free tier project pauses after 7 days idle and takes 20-30 seconds to wake.
        // The default 60s is fine, but waitsForConnectivity turns a brief dead zone into
        // a delay rather than an error.
        configuration.timeoutIntervalForRequest = 45
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    // MARK: - Auth

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    /// Restores the persisted session, or creates a brand new anonymous user.
    /// There is no signup flow -- three taps to onboarded.
    @discardableResult
    func signInIfNeeded() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        let session = try await client.auth.signInAnonymously()
        log.info("Created a new anonymous user.")
        return session.user.id
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    // MARK: - Profile and group RPCs

    func bootstrapProfile(name: String) async throws -> ProfileRow {
        try await rpc("bootstrap_profile", params: ["p_name": name])
    }

    func createGroup() async throws -> GroupRow {
        try await rpcNoParams("create_group")
    }

    func joinGroup(code: String) async throws -> GroupRow {
        try await rpc("join_group", params: ["p_code": code])
    }

    func leaveGroup() async throws {
        try await rpcVoid("leave_group")
    }

    func kickMember(id: String) async throws {
        try await rpcVoid("kick_member", params: ["p_user_id": id])
    }

    func deleteMyData() async throws {
        try await rpcVoid("delete_my_data")
    }

    func registerDeviceToken(_ hexToken: String, environment: String) async throws {
        try await rpcVoid("register_device_token", params: [
            "p_token": hexToken,
            "p_environment": environment,
        ])
    }

    /// The repair path, called on every app foreground. Cheap, and it fixes any push that
    /// never landed.
    func getRoster() async throws -> Roster {
        try await rpcNoParams("get_roster")
    }

    /// The group's code and owner, which the roster blob deliberately does not carry.
    /// RLS restricts this to the caller's own group, so no filter is needed.
    func fetchGroup() async throws -> GroupRow? {
        do {
            let rows: [GroupRow] = try await client
                .from("groups")
                .select("id,code,owner_id")
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: - set-mood Edge Function

    /// Writes the mood and fans out the push in one round trip, then hands back the full
    /// roster so the caller can update its own widgets immediately without a self push.
    ///
    /// Called through `URLSession` rather than the Supabase functions client so that the
    /// 429 and its `retry_after_ms` survive intact.
    func setMood(_ mood: Mood) async throws -> Roster {
        let accessToken: String
        do {
            accessToken = try await client.auth.session.accessToken
        } catch {
            throw MoodCatsError.notAuthenticated
        }

        var request = URLRequest(url: Config.supabaseURL.appending(path: "functions/v1/set-mood"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["mood_id": mood.rawValue])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            log.error("set-mood transport failure: \(error.code.rawValue)")
            throw MoodCatsError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw MoodCatsError.server("no_response")
        }

        switch http.statusCode {
        case 200:
            let roster = try JSONDecoder().decode(Roster.self, from: data)
            if let note = http.value(forHTTPHeaderField: "x-moodcats-push-note") {
                log.warning("set-mood push note: \(note, privacy: .public)")
            }
            return roster

        case 429:
            let body = try? JSONDecoder().decode(RateLimitBody.self, from: data)
            let seconds = Double(body?.retryAfterMs ?? 3000) / 1000
            throw MoodCatsError.rateLimited(retryAfter: seconds)

        default:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let message = body?.error ?? "http_\(http.statusCode)"
            log.error("set-mood failed \(http.statusCode): \(message, privacy: .public)")
            throw MoodCatsError.from(message: message)
        }
    }

    private struct RateLimitBody: Decodable {
        let retryAfterMs: Int?
        enum CodingKeys: String, CodingKey { case retryAfterMs = "retry_after_ms" }
    }

    private struct ErrorBody: Decodable { let error: String? }

    // MARK: - RPC plumbing

    private func rpc<T: Decodable>(_ name: String, params: [String: String]) async throws -> T {
        do {
            return try await client.rpc(name, params: params).execute().value
        } catch {
            throw Self.translate(error)
        }
    }

    private func rpcNoParams<T: Decodable>(_ name: String) async throws -> T {
        do {
            return try await client.rpc(name).execute().value
        } catch {
            throw Self.translate(error)
        }
    }

    private func rpcVoid(_ name: String, params: [String: String]? = nil) async throws {
        do {
            if let params {
                _ = try await client.rpc(name, params: params).execute()
            } else {
                _ = try await client.rpc(name).execute()
            }
        } catch {
            throw Self.translate(error)
        }
    }

    /// PostgREST surfaces our `raise exception 'group_full'` as `PostgrestError.message`.
    private static func translate(_ error: Error) -> MoodCatsError {
        if let error = error as? MoodCatsError { return error }
        if let error = error as? PostgrestError { return .from(message: error.message) }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .dataNotAllowed:
                return .offline
            default:
                return .server(error.localizedDescription)
            }
        }
        return .server(error.localizedDescription)
    }
}
