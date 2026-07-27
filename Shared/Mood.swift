import Foundation

/// The 8 moods.
///
/// The raw value is the mood id and is **stable forever**. Adding a mood means
/// appending a new case with the next integer. Never reorder, never remove, never
/// reuse a number -- ids are already sitting in other people's databases and widgets.
///
/// >>> This table exists in two places and they must stay in sync: <<<
///   - Swift: this file
///   - TypeScript: supabase/functions/set-mood/moods.ts
public enum Mood: Int, CaseIterable, Identifiable, Sendable, Codable {
    case happy = 0
    case sad = 1
    case sleepy = 2
    case angry = 3
    case anxious = 4
    case chill = 5
    case excited = 6
    case hungry = 7

    public var id: Int { rawValue }

    /// Stable machine key. Also the suffix of the asset name.
    public var key: String {
        switch self {
        case .happy: "happy"
        case .sad: "sad"
        case .sleepy: "sleepy"
        case .angry: "angry"
        case .anxious: "anxious"
        case .chill: "chill"
        case .excited: "excited"
        case .hungry: "hungry"
        }
    }

    /// Shown in the app. Localise here if the app is ever translated.
    public var label: String {
        switch self {
        case .happy: "Happy"
        case .sad: "Sad"
        case .sleepy: "Sleepy"
        case .angry: "Angry"
        case .anxious: "Anxious"
        case .chill: "Chill"
        case .excited: "Excited"
        case .hungry: "Hungry"
        }
    }

    /// Used only in the notification body, which the Edge Function builds. Kept here so
    /// the two copies of the table are diffable side by side.
    public var emoji: String {
        switch self {
        case .happy: "😊"
        case .sad: "😢"
        case .sleepy: "😴"
        case .angry: "😠"
        case .anxious: "😰"
        case .chill: "😎"
        case .excited: "🤩"
        case .hungry: "🍜"
        }
    }

    /// Vector PDF in the asset catalog, template rendered.
    public var assetName: String { "cat_\(key)" }

    /// The neutral cat. Used for every empty, unknown and placeholder widget state --
    /// no widget state may ever render blank.
    public static let placeholderAssetName = "cat_unknown"

    /// Tolerant lookup. A mood id from a newer client than this build should degrade to
    /// the neutral cat rather than crash or silently render the wrong animal.
    public static func known(_ id: Int) -> Mood? { Mood(rawValue: id) }
}
