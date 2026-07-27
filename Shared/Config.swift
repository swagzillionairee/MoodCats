import Foundation

/// Every identifier the three targets need to agree on, in one place.
///
/// This file is compiled into MoodCats, MoodCatsWidget AND MoodCatsNotificationService.
/// Nothing here may import UIKit, WidgetKit or Supabase -- the Notification Service
/// Extension runs under a 24 MB memory cap and must stay cheap to load.
public enum Config {

    // MARK: - Supabase

    /// Project: `moodcats` (ref `zewojsliyfgmraoxgndc`, region us-east-1).
    public static let supabaseURL = URL(string: "https://zewojsliyfgmraoxgndc.supabase.co")!

    /// The **anon / publishable** key. This is designed to be public and is safe to ship
    /// in the client -- every table is behind RLS and every mutation is behind an RPC.
    ///
    /// The service role key must NEVER appear in this project under any circumstances.
    /// It belongs only in Edge Function secrets.
    ///
    /// This is the legacy JWT-format anon key rather than the newer `sb_publishable_...`
    /// key, because it is verified to work as both the `apikey` header and the gateway
    /// bearer token for /functions/v1. The publishable key for this project is
    /// `sb_publishable_roL3udUIICeVwG0CP-FB1A_1FNFt54-` if you want to migrate later.
    public static let supabaseAnonKey = """
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpld29qc2xpeWZnbXJhb3hnbmRjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxMTk1NTEsImV4cCI6MjEwMDY5NTU1MX0.qMZECEmWroZAVIEoZWSKIl39XYLr97yWjbdaFG0eIDA
    """

    // MARK: - App Group

    /// **All three targets need this entitlement.** Missing it on the widget is the
    /// classic "why is my widget always empty" bug, and Xcode will not warn you.
    public static let appGroupID = "group.com.huydao.moodcats"

    // MARK: - Bundle identifiers

    public static let appBundleID = "com.huydao.moodcats"
    public static let widgetBundleID = "com.huydao.moodcats.widget"
    public static let notificationServiceBundleID = "com.huydao.moodcats.notificationservice"

    // MARK: - Widget

    /// Passed to `WidgetCenter.shared.reloadTimelines(ofKind:)` by both the app and the
    /// Notification Service Extension, and declared by the widget itself.
    /// Never call `reloadAllTimelines()`.
    public static let widgetKind = "MoodWidget"

    // MARK: - Deep links

    public static let urlScheme = "moodcats"

    /// `moodcats://friend/<profile uuid>` -- what a widget tap opens.
    public static func friendURL(id: String) -> URL? {
        URL(string: "\(urlScheme)://friend/\(id)")
    }

    // MARK: - Product limits

    /// Mirrors `public.max_group_members()` in the database. The server is the authority;
    /// this copy only exists so the UI can say "8" without a round trip.
    public static let maxGroupMembers = 8

    /// Mirrors the rate limit in the `set-mood` Edge Function. The client throttles
    /// locally so users effectively never see the server's 429.
    public static let moodChangeCooldown: TimeInterval = 3

    /// Crockford base32, no I/L/O/U. Mirrors `CODE_ALPHABET` in the database.
    public static let codeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    public static let codeLength = 6
}
