import SwiftUI

/// The cat, rendered as a kaomoji.
///
/// Compiled into the app and the widget, but **not** the Notification Service Extension
/// -- the NSE has a 24 MB memory cap and renders nothing.
///
/// Sizing is by font size rather than by frame, because a face is wide and short (about
/// 3:1) where the old vector art was square. Callers pass the size they want; the view
/// takes exactly the space that needs and no more.
public struct CatFaceView: View {

    public enum Style {
        /// `(=^ω^=)` -- the whole cat.
        case full
        /// `^ω^` -- eyes and muzzle only, for `.accessoryCircular` and other tight spots.
        case compact
    }

    private let text: String
    private let size: CGFloat
    private let weight: Font.Weight

    public init(mood: Mood?, size: CGFloat, style: Style = .full, weight: Font.Weight = .medium) {
        self.text = style == .full ? Mood.face(for: mood) : Mood.compactFace(for: mood)
        self.size = size
        self.weight = weight
    }

    /// For the fixed placeholder faces, and for previews.
    public init(face: String, size: CGFloat, weight: Font.Weight = .medium) {
        self.text = face
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
            // The faces are near-constant width, so this only ever engages in genuinely
            // cramped layouts -- a very large Dynamic Type setting, or the smallest
            // Lock Screen families.
            .minimumScaleFactor(0.4)
            // VoiceOver would read this as "left paren equals caret omega...". Every
            // caller supplies a real label instead.
            .accessibilityHidden(true)
    }
}

// MARK: - Relative time

public enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "2m ago", "just now". Used on the Group screen and the rectangular widget.
    public static func string(from date: Date, relativeTo now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
