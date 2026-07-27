import SwiftUI
import WidgetKit

// MARK: - Entry

struct MoodEntry: TimelineEntry {
    let date: Date
    let state: State

    /// Every one of these has a designed view. None may render blank.
    enum State {
        /// `intent.friend == nil`
        case unconfigured
        /// Roster blob missing or empty.
        case noData
        /// Pinned id is not in the roster anymore.
        case friendGone(name: String)
        /// Match found.
        case normal(name: String, mood: Mood?, updatedAt: Date, id: String, isMe: Bool)
        /// The widget gallery.
        case gallery(name: String, mood: Mood)
    }
}

// MARK: - Provider

struct MoodProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: Date(), state: .gallery(name: "Kim", mood: .sleepy))
    }

    func snapshot(for configuration: MoodWidgetIntent, in context: Context) async -> MoodEntry {
        // The gallery previews with no real data behind it. Show a plausible cat rather
        // than an empty box, or nobody adds the widget.
        if context.isPreview, configuration.friend == nil {
            return MoodEntry(date: Date(), state: .gallery(name: "Kim", mood: .sleepy))
        }
        return entry(for: configuration)
    }

    /// A single entry with reload policy `.never`.
    ///
    /// Pushes drive every update. The widget has no reason to wake itself, because it
    /// cannot fetch anything -- its only data source is App Group storage.
    func timeline(for configuration: MoodWidgetIntent, in context: Context) async -> Timeline<MoodEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: MoodWidgetIntent) -> MoodEntry {
        guard let friend = configuration.friend else {
            return MoodEntry(date: Date(), state: .unconfigured)
        }

        guard let roster = RosterStore.load(), !roster.isEmpty else {
            return MoodEntry(date: Date(), state: .noData)
        }

        guard let member = roster.member(id: friend.id) else {
            let name = RosterStore.knownName(for: friend.id) ?? friend.name
            return MoodEntry(date: Date(), state: .friendGone(name: name))
        }

        return MoodEntry(
            date: Date(),
            state: .normal(
                name: member.name,
                mood: member.mood,
                updatedAt: member.updatedAt,
                id: member.id,
                isMe: member.id == roster.me
            )
        )
    }
}

// MARK: - Widget

struct MoodWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Config.widgetKind,
            intent: MoodWidgetIntent.self,
            provider: MoodProvider()
        ) { entry in
            MoodWidgetView(entry: entry)
        }
        .configurationDisplayName("Friend's Mood")
        .description("One friend's cat, on your Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct MoodCatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodWidget()
    }
}
