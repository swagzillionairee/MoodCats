import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            switch model.stage {
            case .launching:
                LaunchView()
            case .needsName:
                OnboardingView()
            case .needsGroup:
                GroupChoiceView()
            case .widgetTutorial:
                WidgetSetupView(onDone: model.finishWidgetTutorial)
            case .ready:
                MainTabView()
            case .unrecoverable(let message):
                UnrecoverableView(message: message)
            }
        }
        .animation(.snappy, value: model.stage)
        .alert(
            "Hmm",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { model.errorMessage = nil } },
            message: { Text(model.errorMessage ?? "") }
        )
    }
}

// MARK: - Launch

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 20) {
            CatArtView(assetName: Mood.placeholderAssetName)
                .frame(width: 120, height: 120)
                .foregroundStyle(.tint)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct UnrecoverableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't reach MoodCats", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        }
    }
}

// MARK: - Main tabs

private struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Tab.home

    private enum Tab: Hashable { case home, group, settings }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Mood", systemImage: "cat") }
                .tag(Tab.home)

            GroupView()
                .tabItem { Label("Group", systemImage: "person.2") }
                .tag(Tab.group)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: model.highlightedFriendID) { _, newValue in
            // Tapping a widget deep links to that friend.
            if newValue != nil { selection = .group }
        }
    }
}
