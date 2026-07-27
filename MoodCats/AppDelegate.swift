import OSLog
import UIKit
import UserNotifications
import WidgetKit

/// Push plumbing. Kept deliberately thin -- the interesting work happens in the
/// Notification Service Extension, which runs even when this process is dead.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let log = Logger(subsystem: Config.appBundleID, category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Token registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let environment = NotificationManager.apnsEnvironment
        log.info("APNs token registered (\(environment, privacy: .public)).")

        #if DEBUG
        // Phase 0 needs this hex to aim Scripts/push_spike.sh at the device. Marked
        // public so it is readable in Console.app rather than redacted to <private>,
        // and compiled out of Release so a real user's token never lands in a log.
        log.info("APNs device token: \(hex, privacy: .public)")
        #endif

        Task {
            do {
                try await SupabaseService.shared.registerDeviceToken(hex, environment: environment)
            } catch {
                // Not fatal: registration is retried on the next launch, and the widget
                // still repairs itself from get_roster on foreground.
                log.error("Failed to store device token: \(error.localizedDescription)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        log.error("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Foreground delivery

    /// The Notification Service Extension already wrote the roster and reloaded the
    /// widget before this fires. Applying it again here is harmless -- the monotonic
    /// `t` rule turns the second write into a no-op -- and it covers the case where the
    /// extension was skipped or throttled by the system.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        applyPayload(notification.request.content.userInfo)
        // No banner while the user is looking at the app; it still lands quietly in
        // Notification Center.
        return [.list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        applyPayload(response.notification.request.content.userInfo)
    }

    private func applyPayload(_ userInfo: [AnyHashable: Any]) {
        guard let roster = Roster.fromPushPayload(userInfo) else { return }
        guard RosterStore.apply(roster) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        NotificationCenter.default.post(name: .moodCatsRosterDidChange, object: nil)
    }
}

extension Notification.Name {
    static let moodCatsRosterDidChange = Notification.Name("MoodCatsRosterDidChange")
}
