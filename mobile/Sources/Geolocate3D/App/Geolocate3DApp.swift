import SwiftUI
import SwiftData

@main
struct Geolocate3DApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var spatialSessionManager = SpatialSessionManager()
    @State private var backendClient = BackendClient()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .environment(spatialSessionManager)
                .environment(backendClient)
                .preferredColorScheme(.dark)
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
