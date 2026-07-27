import SwiftUI
import UserNotifications

/// Screen 7. Notification status, the widget tutorial again, display name, Delete My Data.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notifications = NotificationManager.shared
    @State private var showingTutorial = false
    @State private var editingName = false
    @State private var draftName = ""
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("You") {
                    Button {
                        draftName = model.displayName
                        editingName = true
                    } label: {
                        LabeledContent("Name", value: model.displayName)
                            .foregroundStyle(.primary)
                    }
                }

                Section {
                    notificationRow
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(notificationFooter)
                }

                Section {
                    Button {
                        showingTutorial = true
                    } label: {
                        Label("How to add the widget", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    Text("Each widget shows one friend. Add one widget per person you want to watch.")
                }

                Section {
                    Button("Delete my data", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Removes your profile, your mood, and this device's notification registration. If you own a group, the group goes too. This can't be undone.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .task { await notifications.refreshStatus() }
            .sheet(isPresented: $showingTutorial) {
                NavigationStack {
                    WidgetSetupView(onDone: {}, isModal: true)
                        .navigationTitle("Add the widget")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .alert("Change your name", isPresented: $editingName) {
                TextField("Name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    Task { await model.rename(to: draftName) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Up to 20 characters. Your friends see this on their widgets.")
            }
            .confirmationDialog(
                "Delete everything?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete my data", role: .destructive) {
                    Task { await model.deleteMyData() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var notificationRow: some View {
        switch notifications.authorizationStatus {
        case .denied:
            Button {
                notifications.openSystemSettings()
            } label: {
                LabeledContent("Status") {
                    Label("Off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

        case .provisional:
            LabeledContent("Status") {
                Label("Quiet", systemImage: "bell.badge")
                    .foregroundStyle(.secondary)
            }
            Button("Turn on banners") {
                Task { await notifications.requestFullAuthorization() }
            }

        case .authorized, .ephemeral:
            LabeledContent("Status") {
                Label("On", systemImage: "bell.fill")
                    .foregroundStyle(.green)
            }

        default:
            Button("Allow notifications") {
                Task { await notifications.requestProvisionalAuthorization() }
            }
        }
    }

    private var notificationFooter: String {
        switch notifications.authorizationStatus {
        case .denied:
            return "Widgets only update when you open MoodCats. Turn notifications on in Settings to get updates in the background."
        case .provisional:
            return "Updates arrive silently and land in Notification Center. Turn on banners if you want to be told out loud."
        default:
            return "MoodCats uses notifications to update your widgets in the background. That's the whole reason it asks."
        }
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
