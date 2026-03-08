import SwiftUI

struct RootTabView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @AppStorage("preferredMode") private var preferredMode = "inside"

    private var isOutdoor: Bool { preferredMode == AppMode.outside.rawValue }

    var body: some View {
        @Bindable var nav = coordinator

        TabView(selection: $nav.selectedTab) {
            if isOutdoor {
                OutdoorMapView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(0)
            } else {
                HomeStack()
                    .tabItem { Label("Home", systemImage: "eyeglasses") }
                    .tag(0)
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
        }
        .tint(.spatialCyan)

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
            case .outdoorCapture:
                OutdoorCaptureView()
            }
        }

        .sheet(item: $nav.activeSheet) { route in
            switch route {
            case .queryConsole(let roomID):
                QueryConsoleView(roomID: roomID)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(32)
                    .presentationBackground(.ultraThinMaterial)
            case .scanResults(let roomID):
                ScanResultsView(roomID: roomID)
                    .presentationDetents([.height(400)])
                    .presentationCornerRadius(32)
            case .objectDetail(let id):
                ObjectDetailView(observationID: id)
                    .presentationDetents([.medium])
            case .framePreview(let detectionID):
                FramePreviewSheet(detectionID: detectionID)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(32)
            }
        }
    }
}

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
                        ObjectDetailView(observationID: id)
                    }
                }
        }
    }
}
