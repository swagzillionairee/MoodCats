import Combine
import SwiftUI
import UIKit

@main
struct MoodCatsApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    // The cheap repair path for any push that never landed.
                    guard phase == .active else { return }
                    model.adoptStoredRoster()
                    Task { await model.refresh() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .moodCatsRosterDidChange)) { _ in
                    model.adoptStoredRoster()
                }
        }
    }
}
