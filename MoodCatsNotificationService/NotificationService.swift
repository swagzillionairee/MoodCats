import OSLog
import UserNotifications
import WidgetKit

/// The reason this architecture works: **this extension runs even when the app is force
/// quit.** It intercepts the alert push before the banner is shown, writes the roster
/// that travelled in the payload into App Group storage, and reloads the widget. The
/// widget itself never makes a network request, and never has to.
///
/// Rules this file obeys, all of which are load bearing:
///   - `contentHandler` is called on **every** path. A missed call means the
///     notification never arrives at all.
///   - `serviceExtensionTimeWillExpire()` is implemented and delivers the original
///     content.
///   - No image work, no networking, no heavy allocation. The NSE memory limit is 24 MB,
///     tighter than the widget's.
///
/// Breakpoints do not hit here by default. Use Debug > Attach to Process by PID, or read
/// these `os_log` lines in Console.app filtered by the extension's bundle id.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var originalContent: UNNotificationContent?
    private var mutableContent: UNMutableNotificationContent?

    private let log = Logger(subsystem: Config.notificationServiceBundleID, category: "NSE")

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.originalContent = request.content
        self.mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent

        // Everything below is synchronous, allocation-light and offline, so the 30 second
        // budget and the 24 MB cap are never in play.
        guard let roster = Roster.fromPushPayload(request.content.userInfo) else {
            // Unknown payload version, or a shape this build cannot read. Deliver the
            // notification untouched rather than swallowing it.
            log.notice("Payload not readable by this build; delivering unmodified.")
            deliver()
            return
        }

        guard RosterStore.apply(roster) else {
            // Stale push. Normal, not an error -- pushes arrive out of order, and the
            // monotonic `t` rule is exactly what makes that harmless.
            log.debug("Roster t=\(roster.t) was not newer than stored; nothing to reload.")
            deliver()
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        log.debug("Applied roster t=\(roster.t), reloaded \(Config.widgetKind, privacy: .public).")
        deliver()
    }

    override func serviceExtensionTimeWillExpire() {
        log.error("NSE ran out of time; delivering original content.")
        deliver()
    }

    /// Calls the handler exactly once, whichever path got here first.
    private func deliver() {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(mutableContent ?? originalContent ?? UNMutableNotificationContent())
    }
}
