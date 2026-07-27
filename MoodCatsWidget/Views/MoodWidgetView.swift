import SwiftUI
import WidgetKit

/// Renders every state from the spec's table across all three families.
///
/// **No state renders blank.** Unconfigured, no data, friend gone, normal and the gallery
/// placeholder each get a designed view, in each family.
///
/// The cats are kaomoji rather than images, so Lock Screen vibrant mode -- which
/// desaturates everything to monochrome -- costs nothing, and there is no rasterisation
/// to go soft at any size. Verify it on device anyway rather than assuming.
struct MoodWidgetView: View {
    let entry: MoodEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(deepLink)
            .containerBackground(for: .widget) {
                // Named colour rather than Color(.systemBackground) so the widget target
                // never has to reach into UIKit.
                switch family {
                case .systemSmall: Color("WidgetBackground")
                default: Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: - systemSmall

    private var small: some View {
        VStack(spacing: 10) {
            CatFaceView(face: presentation.face, size: 27, weight: .medium)

            VStack(spacing: 1) {
                Text(presentation.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - accessoryCircular

    /// The whole widget is about 22 points across, so this uses the compact face --
    /// eyes and muzzle only, no `(=` `=)` frame.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            CatFaceView(face: presentation.compactFace, size: 17, weight: .semibold)
                .padding(3)
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - accessoryRectangular

    private var rectangular: some View {
        HStack(spacing: 8) {
            CatFaceView(face: presentation.face, size: 16, weight: .medium)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - State to pixels

    private struct Presentation {
        let face: String
        let compactFace: String
        let title: String
        let subtitle: String?
        let accessibilityLabel: String
    }

    private var presentation: Presentation {
        switch entry.state {
        case .unconfigured:
            Presentation(
                face: Mood.placeholderFace,
                compactFace: Mood.placeholderCompactFace,
                title: "Pick a friend",
                subtitle: "Long press to choose",
                accessibilityLabel: "No friend chosen. Long press to pick one."
            )

        case .noData:
            Presentation(
                face: Mood.placeholderFace,
                compactFace: Mood.placeholderCompactFace,
                title: "Open MoodCats",
                subtitle: "Join a group to start",
                accessibilityLabel: "Open MoodCats to join a group."
            )

        case .friendGone(let name):
            Presentation(
                face: Mood.placeholderFace,
                compactFace: Mood.placeholderCompactFace,
                title: name,
                subtitle: "left the group",
                accessibilityLabel: "\(name) left the group."
            )

        case .normal(let name, let mood, let updatedAt, _, let isMe):
            Presentation(
                face: Mood.face(for: mood),
                compactFace: Mood.compactFace(for: mood),
                title: isMe ? "\(name) (you)" : name,
                subtitle: subtitle(for: mood, updatedAt: updatedAt),
                accessibilityLabel: mood.map { "\(name) is feeling \($0.label)" } ?? name
            )

        case .gallery(let name, let mood):
            Presentation(
                face: mood.face,
                compactFace: mood.compactFace,
                title: name,
                subtitle: mood.label,
                accessibilityLabel: "\(name) is feeling \(mood.label)"
            )
        }
    }

    private func subtitle(for mood: Mood?, updatedAt: Date) -> String {
        guard let mood else { return RelativeTime.string(from: updatedAt) }
        switch family {
        case .accessoryRectangular:
            return "\(mood.label) · \(RelativeTime.string(from: updatedAt))"
        default:
            return mood.label
        }
    }

    private var deepLink: URL? {
        if case .normal(_, _, _, let id, _) = entry.state {
            return Config.friendURL(id: id)
        }
        return URL(string: "\(Config.urlScheme)://open")
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    MoodWidget()
} timeline: {
    MoodEntry(date: .now, state: .normal(name: "Kim", mood: .sleepy, updatedAt: .now.addingTimeInterval(-400), id: "preview", isMe: false))
    MoodEntry(date: .now, state: .normal(name: "Kim", mood: .excited, updatedAt: .now, id: "preview", isMe: false))
    MoodEntry(date: .now, state: .unconfigured)
    MoodEntry(date: .now, state: .noData)
    MoodEntry(date: .now, state: .friendGone(name: "Kim"))
}

#Preview("Circular", as: .accessoryCircular) {
    MoodWidget()
} timeline: {
    MoodEntry(date: .now, state: .normal(name: "Kim", mood: .chill, updatedAt: .now, id: "preview", isMe: false))
    MoodEntry(date: .now, state: .unconfigured)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    MoodWidget()
} timeline: {
    MoodEntry(date: .now, state: .normal(name: "Kim", mood: .excited, updatedAt: .now.addingTimeInterval(-90), id: "preview", isMe: false))
    MoodEntry(date: .now, state: .friendGone(name: "Kim"))
}
