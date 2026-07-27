import SwiftUI
import UIKit

/// Screen 1. Name entry, max 20 characters. On continue: anonymous sign in has already
/// happened, so this just calls `bootstrap_profile`.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            CatFaceView(mood: .happy, size: 56)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("MoodCats")
                    .font(.largeTitle.bold())
                Text("Share a cat with your friends.\nNo posts, no feed, just a mood.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("What should we call you?", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($nameFocused)
                    .onSubmit { submit() }
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 20 { name = String(newValue.prefix(20)) }
                    }

                Text("\(trimmed.count)/20")
                    .font(.caption)
                    .foregroundStyle(trimmed.isEmpty ? .secondary : .tertiary)
                    .padding(.leading, 4)
            }
            .padding(.horizontal)

            Button(action: submit) {
                if model.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Continue").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trimmed.isEmpty || model.isBusy)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        nameFocused = false
        Task { await model.setName(trimmed) }
    }
}
