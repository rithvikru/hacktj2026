import SwiftUI

@main
struct Geolocate3DApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var spatialSessionManager = SpatialSessionManager()
    @State private var roomStore = RoomStore()
    @State private var backendClient = BackendClient(
        baseURL: URL(
            string: UserDefaults.standard.string(forKey: "backendBaseURL")
                ?? BackendClient.defaultBaseURLString
        ) ?? URL(string: BackendClient.defaultBaseURLString)!
    )
    @State private var wearableStreamManager = WearableStreamSessionManager(
        bridgeMode: WearableBridgeMode.fromStoredValue(
            UserDefaults.standard.string(forKey: "wearableBridgeMode")
        )
    )

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .environment(spatialSessionManager)
                .environment(roomStore)
                .environment(backendClient)
                .environment(wearableStreamManager)
                .preferredColorScheme(.dark)
                .task {
                    wearableStreamManager.attachBackendClient(backendClient)
                    wearableStreamManager.configureIfNeeded()
                }
                .onOpenURL { url in
                    Task {
                        await wearableStreamManager.handleOpenURL(url)
                    }
                }
        }
    }
}
