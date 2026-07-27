import SwiftUI
import UIKit

/// Screen 4. **This screen is load bearing.**
///
/// Users who never add the widget churn within 48 hours, so it is shown once immediately
/// after create or join, again from Settings, and re-prompted on the second launch if no
/// widget has been configured.
struct WidgetSetupView: View {
    let onDone: () -> Void
    var isModal = false

    @State private var step = 0
    @Environment(\.dismiss) private var dismiss

    private static let steps: [Step] = [
        Step(
            title: "Long press your Home Screen",
            detail: "Press and hold any empty spot until the icons start to jiggle.",
            illustration: .jiggle
        ),
        Step(
            title: "Tap + and find MoodCats",
            detail: "The plus button is in the top corner. Search for MoodCats and pick the small widget.",
            illustration: .add
        ),
        Step(
            title: "Long press the widget",
            detail: "Once it's on your Home Screen, press and hold it, then tap Edit Widget.",
            illustration: .edit
        ),
        Step(
            title: "Pick a friend",
            detail: "Each widget shows one person. Want to watch four friends? Add four widgets.",
            illustration: .friend
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, item in
                    StepView(step: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if step < Self.steps.count - 1 {
                    Button {
                        withAnimation { step += 1 }
                    } label: {
                        Text("Next").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for now", action: finish)
                        .font(.subheadline)
                } else {
                    Button {
                        finish()
                    } label: {
                        Text(isModal ? "Done" : "Got it").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func finish() {
        if isModal { dismiss() } else { onDone() }
    }

    fileprivate struct Step {
        let title: String
        let detail: String
        let illustration: Illustration
    }

    fileprivate enum Illustration { case jiggle, add, edit, friend }
}

// MARK: - Step

private struct StepView: View {
    let step: WidgetSetupView.Step
    @State private var animating = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            PhoneFrame {
                switch step.illustration {
                case .jiggle: jiggleArt
                case .add: addArt
                case .edit: editArt
                case .friend: friendArt
                }
            }
            .frame(width: 170, height: 320)

            VStack(spacing: 10) {
                Text(step.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }

    private var jiggleArt: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(1, contentMode: .fit)
                    .rotationEffect(.degrees(animating ? (index.isMultiple(of: 2) ? 2.5 : -2.5) : 0))
            }
        }
        .padding(12)
    }

    private var addArt: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .scaleEffect(animating ? 1.15 : 1)
                Spacer()
            }
            widgetPreview
            Spacer()
        }
        .padding(12)
    }

    private var editArt: some View {
        VStack(spacing: 10) {
            widgetPreview
                .scaleEffect(animating ? 0.95 : 1)
            VStack(spacing: 0) {
                menuRow("Edit Widget", highlighted: true)
                Divider()
                menuRow("Remove Widget", highlighted: false)
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            Spacer()
        }
        .padding(12)
    }

    private var friendArt: some View {
        VStack(spacing: 10) {
            widgetPreview
            VStack(spacing: 0) {
                menuRow("Friend  ›  Kim", highlighted: true)
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            .opacity(animating ? 1 : 0.55)
            Spacer()
        }
        .padding(12)
    }

    private var widgetPreview: some View {
        VStack(spacing: 4) {
            CatFaceView(mood: .sleepy, size: 17)
                .foregroundStyle(.tint)
            Text("Kim").font(.system(size: 10, weight: .semibold))
        }
        .frame(width: 88, height: 88)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private func menuRow(_ title: String, highlighted: Bool) -> some View {
        Text(title)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(highlighted ? Color.accentColor : .secondary)
    }
}

private struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .clipShape(.rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color(.separator), lineWidth: 3)
            }
    }
}
