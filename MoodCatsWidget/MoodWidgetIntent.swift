import AppIntents
import WidgetKit

/// Each widget instance is pinned to exactly one friend. Want to watch four friends? Add
/// four widgets. Unambiguous, and the user controls what they see.
struct MoodWidgetIntent: WidgetConfigurationIntent {

    static let title: LocalizedStringResource = "Pick a Friend"
    static let description = IntentDescription(
        "Choose whose cat this widget shows. Add one widget per friend."
    )

    @Parameter(title: "Friend")
    var friend: FriendEntity?

    init() {}

    init(friend: FriendEntity?) {
        self.friend = friend
    }
}
