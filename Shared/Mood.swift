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

    /// Stable machine key.
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

    // MARK: - Faces
    //
    // The cat is a kaomoji, not an image. `(=` and `=)` are the ears and cheeks, `ω` is
    // the muzzle, and **only the eyes change** -- the same "one body, face-only
    // variation" rule the vector art followed, except now it is enforced by the string
    // itself rather than by a drawing pipeline.
    //
    // Text beats art here for three reasons: it is resolution independent at every
    // widget size for free, it is already monochrome so Lock Screen vibrant mode costs
    // nothing, and the widget and notification extensions no longer need an asset
    // catalog at all.
    //
    // CHARACTER SET, and why it is this narrow:
    //   ( ) = ^ T -    ASCII
    //   ò ó ° ¯ ·      Latin-1 Supplement
    //   ω              Greek (U+03C9)
    //   ★ ◕            Misc Symbols / Geometric Shapes
    //
    // Every one of those is in the iOS system font or its guaranteed fallback chain.
    // Deliberately NOT used, despite being common in cat kaomoji:
    //   ﻌ (U+FECC) is an ARABIC letter. It renders, but it drags bidirectional text
    //     resolution into a widget layout, which is not a thing to discover on a Lock
    //     Screen.
    //   ฅ (U+0E05, Thai) and ᴥ (U+1D25) depend on fonts that are not guaranteed, and
    //     degrade to tofu boxes rather than to something merely uglier.

    /// The full face. Seven characters, near-constant width, so a mood change never
    /// shifts the layout around it.
    public var face: String {
        switch self {
        case .happy: "(=^ω^=)"
        case .sad: "(=TωT=)"
        case .sleepy: "(=-ω-=)"
        case .angry: "(=òωó=)"
        case .anxious: "(=°ω°=)"
        case .chill: "(=¯ω¯=)"
        case .excited: "(=★ω★=)"
        case .hungry: "(=◕ω◕=)"
        }
    }

    /// Eyes and muzzle only, for places too tight for the full frame -- principally
    /// `.accessoryCircular`, where the whole widget is about 22 points across.
    public var compactFace: String {
        String(face.dropFirst(2).dropLast(2))
    }

    /// The neutral cat. Used for every empty, unknown and placeholder state -- no widget
    /// state may ever render blank.
    public static let placeholderFace = "(=·ω·=)"

    /// Eyes and muzzle of the neutral cat.
    public static let placeholderCompactFace = "·ω·"

    /// Tolerant lookup. A mood id from a newer client than this build should degrade to
    /// the neutral face rather than crash or silently show the wrong one.
    public static func known(_ id: Int) -> Mood? { Mood(rawValue: id) }

    /// The face for a possibly-unknown mood id.
    public static func face(for mood: Mood?) -> String {
        mood?.face ?? placeholderFace
    }

    /// The compact face for a possibly-unknown mood id.
    public static func compactFace(for mood: Mood?) -> String {
        mood?.compactFace ?? placeholderCompactFace
    }
}
