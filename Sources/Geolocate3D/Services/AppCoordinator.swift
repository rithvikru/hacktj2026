import SwiftUI

@Observable
@MainActor
final class AppCoordinator {
    var selectedTab: Int = 0
    var homeNavPath = NavigationPath()

    var activeFullScreen: FullScreenRoute?
    var activeSheet: SheetRoute?

    private var pendingNavRoute: NavigationRoute?

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

    func finishScanAndShowTwin(roomID: UUID) {
        pendingNavRoute = .roomTwin(roomID: roomID)
        dismissFullScreen()
    }

    func handleFullScreenDismissed() {
        guard let route = pendingNavRoute else { return }
        pendingNavRoute = nil
        selectedTab = 0
        push(route)
    }
}
