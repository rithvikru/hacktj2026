import SwiftUI

struct RootTabView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var nav = coordinator

        TabView(selection: $nav.selectedTab) {
            HomeStack()
                .tabItem { Label("Spaces", systemImage: "square.grid.2x2") }
                .tag(0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)
        }
        .tint(.spatialCyan)
        // Immersive AR flows — fullScreenCover with onDismiss (Fix 5)
        .fullScreenCover(item: $nav.activeFullScreen, onDismiss: {
            coordinator.handleFullScreenDismissed()
        }) { route in
            switch route {
            case .scanRoom:
                ScanRoomView()
            case .liveSearch(let roomID):
                LiveSearchView(roomID: roomID)
            case .companionTarget:
                CompanionTargetStubView()
            }
        }
        // Contextual sheets
        .sheet(item: $nav.activeSheet) { route in
            switch route {
            case .queryConsole(let roomID):
                QueryConsoleView(roomID: roomID)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(24)
                    .presentationBackground(Color.obsidian)
            case .scanResults(let roomID):
                ScanResultsStubView(roomID: roomID)
                    .presentationDetents([.height(400)])
                    .presentationCornerRadius(24)
            case .objectDetail(let id):
                ObjectDetailStubView(observationID: id)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Home Navigation Stack

struct HomeStack: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var nav = coordinator

        NavigationStack(path: $nav.homeNavPath) {
            HomeView()
                .navigationDestination(for: NavigationRoute.self) { route in
                    switch route {
                    case .roomTwin(let id):
                        RoomTwinView(roomID: id)
                    case .hiddenSearch(let id):
                        HiddenSearchView(roomID: id)
                    case .objectDetail(let id):
                        ObjectDetailStubView(observationID: id)
                    }
                }
        }
    }
}
