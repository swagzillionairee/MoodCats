import SwiftUI
import UIKit

/// Screen 2. Calls `create_group` and shows the 6 character code large and monospaced.
struct CreateGroupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if let code = model.group?.code {
                Text("Your group code")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .kerning(6)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 28)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                    .textSelection(.enabled)
                    .accessibilityLabel("Group code \(code.map(String.init).joined(separator: " "))")

                ShareLink(item: shareMessage(code: code)) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Text("Friends enter this in MoodCats to join you.\nYou can find it again on the Group tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("Continue", action: model.proceedToWidgetSetup)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.horizontal)
            } else {
                ProgressView("Making your group…")
                Spacer()
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Create")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.group != nil)
        .task {
            guard model.group == nil else { return }
            await model.createGroup()
        }
    }

    private func shareMessage(code: String) -> String {
        "Join me on MoodCats. Group code: \(code)"
    }
}
