import SwiftUI

@main
struct PofudukApp: App {
    @State private var coordinator = AppCoordinator(container: DependencyContainer())

    var body: some Scene {
        WindowGroup {
            coordinator.rootView()
        }
    }
}
