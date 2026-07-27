import Foundation
import OSLog
import SwiftUI
import WidgetKit

/// The app's whole state machine. One object, observed by every screen.
@Observable
@MainActor
final class AppModel {

    enum Stage: Equatable {
        case launching
        case needsName
        case needsGroup
        case widgetTutorial
        case ready
        case unrecoverable(String)
    }

    // MARK: - Observed state

    var stage: Stage = .launching
    var roster: Roster?
    var group: GroupRow?
    var errorMessage: String?
    var isBusy = false

    /// Set when the user opens the app by tapping a widget, so the Group screen can
    /// scroll to that friend.
    var highlightedFriendID: String?

    /// Drives the Group tab badge-free "you haven't added a widget yet" nudge.
    var shouldNudgeWidgetSetup = false

    private var moodCooldownUntil: Date?
    private let log = Logger(subsystem: Config.appBundleID, category: "AppModel")
    private let service = SupabaseService.shared

    private enum StorageKey {
        static let launchCount = "moodcats.launchCount"
        static let sawWidgetTutorial = "moodcats.sawWidgetTutorial"
    }

    // MARK: - Derived state

    var myID: String? { roster?.me ?? service.currentUserID?.uuidString.lowercased() }

    var me: RosterMember? {
        guard let myID else { return nil }
        return roster?.member(id: myID)
    }

    var myMood: Mood? { me?.mood }

    var displayName: String { me?.name ?? "" }

    var friends: [RosterMember] { roster?.friends ?? [] }

    var isOwner: Bool {
        guard let group, let myID else { return false }
        return group.ownerId.uuidString.lowercased() == myID.lowercased()
    }

    var isInGroup: Bool { roster?.groupId != nil }

    var moodsAreThrottled: Bool {
        guard let until = moodCooldownUntil else { return false }
        return until > Date()
    }

    // MARK: - Launch

    func start() async {
        stage = .launching

        // Counted here and nowhere else. evaluateWidgetNudge() also runs on every
        // foreground refresh, so incrementing there would call a single long session
        // dozens of "launches".
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: StorageKey.launchCount) + 1, forKey: StorageKey.launchCount)

        do {
            _ = try await service.signInIfNeeded()
        } catch {
            log.error("Sign in failed: \(error.localizedDescription)")
            stage = .unrecoverable("Couldn't reach MoodCats. Check your connection and reopen the app.")
            return
        }

        // Register on EVERY launch, not just the first. Tokens rotate.
        NotificationManager.shared.registerForRemoteNotifications()
        await NotificationManager.shared.refreshStatus()

        do {
            let roster = try await service.getRoster()
            adopt(roster)
            if roster.groupId == nil {
                stage = .needsGroup
            } else {
                await loadGroup()
                stage = .ready
                await evaluateWidgetNudge()
            }
        } catch MoodCatsError.profileMissing {
            stage = .needsName
        } catch {
            // Offline on a cold launch: fall back to whatever the widget is already
            // showing rather than blocking the user behind a spinner.
            if let cached = RosterStore.load() {
                roster = cached
                stage = cached.groupId == nil ? .needsGroup : .ready
                present(error)
            } else {
                stage = .unrecoverable("Couldn't load your group. Check your connection and reopen the app.")
            }
        }
    }

    // MARK: - Onboarding

    func setName(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(name.count) else {
            errorMessage = MoodCatsError.invalidDisplayName.errorDescription
            return
        }
        await perform {
            _ = try await self.service.bootstrapProfile(name: name)
            let roster = try await self.service.getRoster()
            self.adopt(roster)
            self.stage = roster.groupId == nil ? .needsGroup : .ready
        }
    }

    /// Creates the group but deliberately stays on the Create Group screen. The whole
    /// point of that screen is the code -- moving the user straight to the widget
    /// tutorial would flash it past them and leave them with no way to invite anyone.
    /// `proceedToWidgetSetup()` is what advances, once they have read or shared it.
    func createGroup() async {
        await perform {
            self.group = try await self.service.createGroup()
            await self.prepareForGroupLife()
        }
    }

    /// Joining has nothing to show, so it advances immediately.
    func joinGroup(code: String) async {
        let cleaned = Self.sanitize(code: code)
        guard cleaned.count == Config.codeLength else {
            errorMessage = MoodCatsError.groupNotFound.errorDescription
            return
        }
        await perform {
            self.group = try await self.service.joinGroup(code: cleaned)
            await self.prepareForGroupLife()
            self.stage = .widgetTutorial
        }
    }

    func proceedToWidgetSetup() {
        stage = .widgetTutorial
    }

    /// Permission and a fresh roster, without moving the user off their current screen.
    private func prepareForGroupLife() async {
        // Provisional authorization grants without ever showing a prompt.
        await NotificationManager.shared.requestProvisionalAuthorization()
        if let roster = try? await service.getRoster() { adopt(roster) }
    }

    func finishWidgetTutorial() {
        UserDefaults.standard.set(true, forKey: StorageKey.sawWidgetTutorial)
        shouldNudgeWidgetSetup = false
        stage = .ready
    }

    // MARK: - Moods

    func setMood(_ mood: Mood) async {
        guard !moodsAreThrottled else { return }
        // Throttle locally so the server's 429 is a backstop users effectively never see.
        moodCooldownUntil = Date().addingTimeInterval(Config.moodChangeCooldown)

        await perform {
            let roster = try await self.service.setMood(mood)
            self.adopt(roster)
        }
    }

    // MARK: - Group management

    func loadGroup() async {
        group = try? await service.fetchGroup()
    }

    func leaveGroup() async {
        await perform {
            try await self.service.leaveGroup()
            self.group = nil
            let roster = try await self.service.getRoster()
            self.adopt(roster)
            self.stage = .needsGroup
        }
    }

    func kick(_ member: RosterMember) async {
        await perform {
            try await self.service.kickMember(id: member.id)
            let roster = try await self.service.getRoster()
            self.adopt(roster)
        }
    }

    func rename(to newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(name.count) else {
            errorMessage = MoodCatsError.invalidDisplayName.errorDescription
            return
        }
        await perform {
            _ = try await self.service.bootstrapProfile(name: name)
            let roster = try await self.service.getRoster()
            self.adopt(roster)
        }
    }

    /// Row gone, tokens gone, App Group cleared, signed out.
    func deleteMyData() async {
        await perform {
            try await self.service.deleteMyData()
            await self.service.signOut()
            RosterStore.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
            UserDefaults.standard.removeObject(forKey: StorageKey.sawWidgetTutorial)
            self.roster = nil
            self.group = nil
            self.stage = .needsName
            _ = try? await self.service.signInIfNeeded()
        }
    }

    // MARK: - Refresh

    /// The cheap repair path for any push that never landed. Called on every foreground.
    func refresh() async {
        guard stage == .ready || stage == .needsGroup else { return }
        do {
            let roster = try await service.getRoster()
            adopt(roster)
            if roster.groupId != nil, group == nil { await loadGroup() }
            if roster.groupId == nil, stage == .ready {
                // Kicked, or the owner deleted the group while we were away.
                group = nil
                stage = .needsGroup
            }
            await evaluateWidgetNudge()
        } catch MoodCatsError.profileMissing {
            stage = .needsName
        } catch {
            log.error("Foreground refresh failed: \(error.localizedDescription)")
        }
    }

    /// The Notification Service Extension wrote a newer blob while the app was alive.
    func adoptStoredRoster() {
        guard let stored = RosterStore.load() else { return }
        guard stored.t > (roster?.t ?? .min) else { return }
        roster = stored
    }

    // MARK: - Deep links

    func handle(url: URL) {
        guard url.scheme == Config.urlScheme, url.host == "friend" else { return }
        let id = url.lastPathComponent
        highlightedFriendID = id.isEmpty ? nil : id
    }

    // MARK: - Widget nudge

    /// "Re-prompt on second launch if no widget has been configured." Users who never add
    /// the widget churn within 48 hours, so this screen is load bearing.
    func evaluateWidgetNudge() async {
        guard stage == .ready, isInGroup else { return }
        // Not on the very first launch -- they have just been walked through it.
        guard UserDefaults.standard.integer(forKey: StorageKey.launchCount) >= 2 else { return }
        shouldNudgeWidgetSetup = await !Self.hasInstalledWidget()
    }

    private static func hasInstalledWidget() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets):
                    continuation.resume(returning: widgets.contains { $0.kind == Config.widgetKind })
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Plumbing

    /// Writes to the App Group and reloads only our widget kind. Never
    /// `reloadAllTimelines()`.
    private func adopt(_ incoming: Roster) {
        roster = incoming
        RosterStore.localUserID = incoming.me
        if RosterStore.apply(incoming) {
            WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        let mapped = (error as? MoodCatsError) ?? .server(error.localizedDescription)
        errorMessage = mapped.errorDescription
        log.error("\(String(describing: mapped), privacy: .public)")
    }

    /// Uppercases, strips whitespace, and drops anything outside `CODE_ALPHABET`.
    static func sanitize(code: String) -> String {
        let allowed = Set(Config.codeAlphabet)
        return String(code.uppercased().filter { allowed.contains($0) }.prefix(Config.codeLength))
    }
}
