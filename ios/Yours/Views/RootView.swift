import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch model.phase {
            case .loading:
                ProgressView()
                    .tint(Theme.accent)
            case .landing:
                LandingView()
            case .chat:
                ChatScreen()
            case .locked:
                LockedView()
            case .sleeping:
                SleepView()
            }
        }
    }
}
