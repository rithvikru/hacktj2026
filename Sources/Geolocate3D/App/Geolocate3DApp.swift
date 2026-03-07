import SwiftUI
import SwiftData

@main
struct Geolocate3DApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
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
