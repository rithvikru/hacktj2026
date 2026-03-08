import SwiftUI
import SceneKit

struct RoomTwinView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RoomStore.self) private var roomStore
    @State private var viewModel: RoomTwinViewModel
    @State private var projectedPositions: [UUID: CGPoint] = [:]

    init(roomID: UUID) {
        self.roomID = roomID
        _viewModel = State(initialValue: RoomTwinViewModel(roomID: roomID))
    }

    var body: some View {
        ZStack {

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
            viewModel.loadRoom(roomStore: roomStore)
        }
    }
}
