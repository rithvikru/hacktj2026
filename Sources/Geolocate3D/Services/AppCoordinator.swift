import SwiftUI

/// Central navigation state manager.
/// Uses onDismiss-based transitions instead of fragile asyncAfter delays (Fix 5).
@Observable
@MainActor
final class AppCoordinator {
    var selectedTab: Int = 0
    var homeNavPath = NavigationPath()

    // Modal state
    var activeFullScreen: FullScreenRoute?
    var activeSheet: SheetRoute?

    // Pending route to push after fullScreenCover dismissal
    private var pendingNavRoute: NavigationRoute?

    // MARK: - Navigation Intents

    func push(_ route: NavigationRoute) {
        homeNavPath.append(route)
    }

    func presentImmersive(_ route: FullScreenRoute) {
        activeFullScreen = route
    }

    func presentSheet(_ route: SheetRoute) {
        activeSheet = route
    }

    func dismissFullScreen() {
        activeFullScreen = nil
    }

    func dismissSheet() {
        activeSheet = nil
    }

    /// Schedule a navigation push after fullScreenCover dismisses.
    /// The actual push happens in `handleFullScreenDismissed()`.
    func finishScanAndShowTwin(roomID: UUID) {
        pendingNavRoute = .roomTwin(roomID: roomID)
        dismissFullScreen()
    }

    /// Called from `.fullScreenCover(onDismiss:)` — fires exactly when dismiss animation completes.
    func handleFullScreenDismissed() {
        guard let route = pendingNavRoute else { return }
        pendingNavRoute = nil
        selectedTab = 0
        push(route)
    }
}
