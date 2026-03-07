import SwiftUI
import SceneKit
import SwiftData

/// 3D room viewer using SceneKit (Fix 1/3: no visionOS RealityView or Entity(named:)).
/// Loads USDZ via SCNScene with built-in orbit/zoom/pan. Annotation pins positioned
/// via scnView.projectPoint() converting 3D world positions to 2D screen coordinates.
struct RoomTwinView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RoomTwinViewModel
    @State private var projectedPositions: [UUID: CGPoint] = [:]

    init(roomID: UUID) {
        self.roomID = roomID
        _viewModel = State(initialValue: RoomTwinViewModel(roomID: roomID))
    }

    var body: some View {
        ZStack {
            // SceneKit 3D view with built-in camera control
            SceneViewRepresentable(
                roomID: roomID,
                observations: viewModel.observations,
                showScaffold: viewModel.showScaffold,
                showObjects: viewModel.showObjects,
                showHeatmap: viewModel.showHeatmap,
                showDense: viewModel.showDense,
                projectedPositions: $projectedPositions
            )
            .ignoresSafeArea()

            // SwiftUI annotation overlays positioned via screen projection
            if viewModel.showObjects {
                ForEach(viewModel.observations) { obs in
                    if let screenPos = projectedPositions[obs.id] {
                        AnnotationPin(observation: obs)
                            .position(screenPos)
                            .onTapGesture {
                                coordinator.presentSheet(.objectDetail(observationID: obs.id))
                            }
                    }
                }
            }

            // Layer toggle bar
            VStack {
                Spacer()
                LayerToggleBar(
                    showScaffold: $viewModel.showScaffold,
                    showObjects: $viewModel.showObjects,
                    showHeatmap: $viewModel.showHeatmap,
                    showDense: $viewModel.showDense
                )
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(viewModel.roomName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Live Search", systemImage: "arkit") {
                        coordinator.presentImmersive(.liveSearch(roomID: roomID))
                    }
                    Button("Query", systemImage: "text.magnifyingglass") {
                        coordinator.presentSheet(.queryConsole(roomID: roomID))
                    }
                    Button("Hidden Search", systemImage: "eye.slash") {
                        coordinator.push(.hiddenSearch(roomID: roomID))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            viewModel.loadRoom(modelContext: modelContext)
        }
    }
}
