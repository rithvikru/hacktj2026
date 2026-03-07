import SwiftUI
import SwiftData

@main
struct Geolocate3DApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var spatialSessionManager = SpatialSessionManager()
    @State private var backendClient = BackendClient()
    @State private var wearableStreamManager = WearableStreamSessionManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .environment(spatialSessionManager)
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
        .modelContainer(for: [
            RoomRecord.self,
            ObjectObservation.self,
            ObjectPrototype.self,
            SceneNode.self,
            SceneEdge.self,
            ObjectHypothesis.self
        ])
    }
}
