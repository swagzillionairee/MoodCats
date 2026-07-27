import Foundation
import OSLog
import UIKit
import UserNotifications

/// Notification permission and APNs token registration.
@Observable
@MainActor
final class NotificationManager {

    static let shared = NotificationManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let log = Logger(subsystem: Config.appBundleID, category: "Notifications")

    /// `nonisolated` so the singleton can be constructed from a SwiftUI property
    /// initialiser without an actor-isolation diagnostic. It stores nothing that needs
    /// the main actor at construction time; everything that touches UIKit is a method.
    nonisolated private init() {}

    /// Which APNs host the Edge Function should use for tokens minted by this build.
    ///
    /// Xcode debug builds get sandbox tokens; TestFlight and App Store builds are always
    /// compiled Release and get production tokens. The environment is stored per token in
    /// the database rather than assumed, because a sandbox token posted to the production
    /// host comes back `400 BadDeviceToken` and the whole feature dies silently.
    ///
    /// Caveat worth knowing: a Release-configured build run straight from Xcode still
    /// receives a sandbox token while reporting "production". If you need to test that
    /// configuration on device, read `aps-environment` out of the embedded provisioning
    /// profile instead.
    static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        log.debug("Notification authorization: \(settings.authorizationStatus.rawValue)")
    }

    /// Requested immediately after the user creates or joins a group.
    ///
    /// Provisional authorization grants without ever showing a prompt and delivers
    /// quietly to Notification Center. Combined with `interruption-level: passive` on the
    /// payload, that is what stops notification fatigue from killing the update path --
    /// and the Notification Service Extension still fires, which is the part that
    /// actually matters.
    func requestProvisionalAuthorization() async {
        await refreshStatus()
        guard authorizationStatus == .notDetermined else {
            registerForRemoteNotifications()
            return
        }
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound, .provisional])
        } catch {
            log.error("Provisional authorization failed: \(error.localizedDescription)")
        }
        await refreshStatus()
        registerForRemoteNotifications()
    }

    /// The Settings "upgrade to banners" toggle, for people who want loud notifications.
    @discardableResult
    func requestFullAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshStatus()
        registerForRemoteNotifications()
        return granted
    }

    /// Called on **every** launch, not just the first. Tokens rotate.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
