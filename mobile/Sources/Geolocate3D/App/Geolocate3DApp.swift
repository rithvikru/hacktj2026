import SwiftUI

@main
struct Geolocate3DApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingChoiceView()
                }
            }
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
                NSLog("[Geolocate3D] onOpenURL: %@", url.absoluteString)
                Task {
                    await wearableStreamManager.handleOpenURL(url)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {

                    NSLog("[Geolocate3D] scenePhase → active, syncing SDK state")
                    wearableStreamManager.syncBridgeState()
                    wearableStreamManager.configureIfNeeded()
                }
            }
        }
    }
}
