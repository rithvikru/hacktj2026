import SwiftUI
import SceneKit
import SwiftData

/// 3D room viewer using SceneKit (Fix 1/3: no visionOS RealityView or Entity(named:)).
/// Loads USDZ via SCNScene with built-in orbit/zoom/pan. Annotation pins positioned
/// via scnView.projectPoint() converting 3D world positions to 2D screen coordinates.
struct RoomTwinView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BackendClient.self) private var backendClient
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
                hypotheses: viewModel.hypotheses,
                showScaffold: viewModel.showScaffold,
                showObjects: viewModel.showObjects,
                showHeatmap: viewModel.showHeatmap,
                showDense: viewModel.showDense,
                denseAssetURL: viewModel.denseAssetURL,
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
                if viewModel.reconstructionStatus != .complete || viewModel.statusMessage != nil {
                    HStack(spacing: 8) {
                        if viewModel.reconstructionStatus == .failed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.warningAmber)
                        } else {
                            ProgressView()
                                .tint(.spatialCyan)
                        }
                        Text(statusLine)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
                }

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
                    Button("Refresh Dense Assets", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refreshAssets(
                                modelContext: modelContext,
                                backendClient: backendClient
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadRoom(
                modelContext: modelContext,
                backendClient: backendClient
            )
        }
        .onChange(of: viewModel.showDense) { _, showDense in
            guard showDense, viewModel.denseAssetURL == nil else { return }
            Task {
                await viewModel.refreshAssets(
                    modelContext: modelContext,
                    backendClient: backendClient
                )
            }
        }
    }

    private var statusLine: String {
        if let statusMessage = viewModel.statusMessage {
            return statusMessage
        }
        switch viewModel.reconstructionStatus {
        case .pending:
            return "Dense reconstruction not started yet."
        case .uploading:
            return "Uploading scan assets for reconstruction."
        case .processing:
            return "Reconstruction is processing in the background."
        case .complete:
            return "Dense reconstruction ready."
        case .failed:
            return "Dense reconstruction failed."
        }
    }
}
