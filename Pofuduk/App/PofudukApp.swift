import SwiftUI

@main
struct PofudukApp: App {
    @State private var coordinator: AppCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = DependencyContainer.app()
        _coordinator = State(initialValue: AppCoordinator(container: container))
        BackgroundRefresh.register { await container.backgroundRefresh() }
        #if DEBUG
        VoiceExporter.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            coordinator.rootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}
