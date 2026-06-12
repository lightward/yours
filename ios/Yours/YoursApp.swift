import SwiftUI

@main
struct YoursApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.themePreference.colorScheme)
                .task { await model.start() }
        }
    }
}
