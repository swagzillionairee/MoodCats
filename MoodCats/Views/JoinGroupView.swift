import SwiftUI
import UIKit

/// Screen 3. Six character entry, auto uppercase, restricted to `CODE_ALPHABET`.
/// Failures are surfaced specifically: bad code, group full, already in a group.
struct JoinGroupView: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var focused: Bool

    private var isComplete: Bool { code.count == Config.codeLength }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            CatArtView(assetName: Mood.chill.assetName)
                .frame(width: 100, height: 100)
                .foregroundStyle(.tint)

            Text("Enter the 6 character code")
                .font(.headline)

            codeBoxes
                .overlay {
                    // Invisible field carries the real input; the boxes are just chrome.
                    TextField("", text: $code)
                        .focused($focused)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .onSubmit(submit)
                        .onChange(of: code) { _, newValue in
                            // No I, L, O or U -- Crockford base32, same as the server.
                            code = AppModel.sanitize(code: newValue)
                        }
                        .opacity(0.001)
                        .accessibilityLabel("Group code")
                }
                .onTapGesture { focused = true }

            Text("Letters and numbers only. No I, L, O or U.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: submit) {
                if model.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Join").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isComplete || model.isBusy)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private var codeBoxes: some View {
        HStack(spacing: 8) {
            ForEach(0..<Config.codeLength, id: \.self) { index in
                let character = index < code.count
                    ? String(code[code.index(code.startIndex, offsetBy: index)])
                    : ""
                Text(character)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .frame(width: 44, height: 58)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(index == code.count ? Color.accentColor : .clear, lineWidth: 2)
                    }
            }
        }
    }

    private func submit() {
        guard isComplete else { return }
        focused = false
        Task { await model.joinGroup(code: code) }
    }
}
