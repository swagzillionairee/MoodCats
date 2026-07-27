import SwiftUI
import UIKit

/// The fork between screens 2 and 3: create a group, or join one with a code.
struct GroupChoiceView: View {
    @Environment(AppModel.self) private var model
    @State private var route: Route?

    private enum Route: Hashable { case create, join }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                CatArtView(assetName: Mood.excited.assetName)
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("One group, up to \(Config.maxGroupMembers) people")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Start one and share the code, or enter a friend's.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        route = .create
                    } label: {
                        Text("Create a group").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        route = .join
                    } label: {
                        Text("Join with a code").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding()
            .navigationDestination(item: $route) { route in
                switch route {
                case .create: CreateGroupView()
                case .join: JoinGroupView()
                }
            }
        }
    }
}
