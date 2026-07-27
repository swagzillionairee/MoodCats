import SwiftUI
import UIKit

/// Screen 5. A grid of the 8 cats. Tap sets your mood.
///
/// On success the returned roster is written to the App Group and only our widget kind is
/// reloaded, so the user's own widgets update instantly with no self push.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Mood.allCases) { mood in
                            MoodTile(
                                mood: mood,
                                isSelected: model.myMood == mood,
                                isDisabled: model.moodsAreThrottled && model.myMood != mood
                            ) {
                                Task { await model.setMood(mood) }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if model.shouldNudgeWidgetSetup {
                        widgetNudge
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("How are you?")
            .refreshable { await model.refresh() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CatFaceView(mood: model.myMood, size: 54, weight: .semibold)
                .foregroundStyle(.tint)
                .contentTransition(.opacity)
                .animation(.snappy, value: model.myMood)
                .accessibilityHidden(false)
                .accessibilityLabel(model.myMood.map { "You're feeling \($0.label)" } ?? "No mood set")

            if let mood = model.myMood {
                Text("You're feeling \(mood.label.lowercased())")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var widgetNudge: some View {
        NavigationLink {
            WidgetSetupView(onDone: {}, isModal: true)
                .navigationTitle("Add the widget")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a widget").font(.subheadline.weight(.semibold))
                    Text("MoodCats lives on your Home Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

private struct MoodTile: View {
    let mood: Mood
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                CatFaceView(mood: mood, size: 24, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(mood.label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
