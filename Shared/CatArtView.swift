import SwiftUI

/// The cat, rendered from a vector PDF as a template image.
///
/// Compiled into the app and the widget, but **not** the Notification Service Extension
/// -- the NSE has a 24 MB memory cap and must do no image work at all.
///
/// Template rendering is what makes `.foregroundStyle` tinting work and what makes Lock
/// Screen vibrant mode free: vibrant desaturates everything to monochrome, and this art
/// is already monochrome vector.
public struct CatArtView: View {
    private let assetName: String

    public init(assetName: String) {
        self.assetName = assetName
    }

    public init(mood: Mood?) {
        self.assetName = mood?.assetName ?? Mood.placeholderAssetName
    }

    public var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
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
