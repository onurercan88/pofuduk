import SwiftUI

/// Owns top-level navigation. Onboarding, settings and other features hook in here in later phases.
@MainActor
@Observable
final class AppCoordinator {
    private let container: DependencyContainer
    private let homeViewModel: HomeViewModel

    init(container: DependencyContainer) {
        self.container = container
        self.homeViewModel = container.makeHomeViewModel()
    }

    @ViewBuilder
    func rootView() -> some View {
        HomeView(viewModel: homeViewModel)
    }
}
