import SwiftUI
import RealityKit
import ARKit
import SwiftData

struct LiveSearchView: View {
    let roomID: UUID?
    let initialRouteTarget: LiveRouteTarget?
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SpatialSessionManager.self) private var sessionManager
    @Environment(BackendClient.self) private var backendClient
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LiveSearchViewModel()
    @State private var relocMonitor = RelocalizationMonitor()

    init(roomID: UUID?, initialRouteTarget: LiveRouteTarget? = nil) {
        self.roomID = roomID
        self.initialRouteTarget = initialRouteTarget
    }

    var body: some View {
        ZStack {
            // AR camera feed via UIKit ARView bridge (Fix 1: iOS-correct, not visionOS RealityView)
            ARViewRepresentable(
                viewModel: viewModel,
                sessionManager: sessionManager,
                roomID: roomID,
                backendClient: backendClient
            )
                .ignoresSafeArea()

            // SwiftUI overlay — tooltips positioned via screen-space projection
            ForEach(viewModel.screenProjectedObservations) { obs in
                ObjectTooltipOverlay(observation: obs)
                    .position(x: obs.screenX, y: obs.screenY - 40)
            }

            // UI chrome
            VStack {
                // Top bar: dismiss + tracking status
                HStack {
                    Button { coordinator.dismissFullScreen() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Spacer()
                    TrackingStatusBadge(quality: trackingQuality)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Relocalization banner
                if relocMonitor.state == .relocalizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.spatialCyan)
                        Text(relocMonitor.statusMessage)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.elevatedSurface.opacity(0.9), in: Capsule())
                    .padding(.top, 8)
                } else if relocMonitor.state == .failed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.warningAmber)
                        Text(relocMonitor.statusMessage)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.warningAmber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.elevatedSurface.opacity(0.9), in: Capsule())
                    .padding(.top, 8)
                }

                Spacer()

                // Object count indicator
                if !viewModel.activeObservations.isEmpty {
                    HStack(spacing: 6) {
                        Text("\(viewModel.activeObservations.count)")
                            .font(SpatialFont.dataLarge)
                            .foregroundStyle(.white)
                        Text("objects detected")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }

                if let result = viewModel.currentResult {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.label)
                            .font(SpatialFont.headline)
                            .foregroundStyle(.white)
                        Text(result.explanation)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                        if let routeStatusText = viewModel.routeStatusText {
                            Label(routeStatusText, systemImage: viewModel.routeWaypoints.isEmpty ? "exclamationmark.triangle.fill" : "figure.walk")
                                .font(SpatialFont.caption)
                                .foregroundStyle(viewModel.routeWaypoints.isEmpty ? .warningAmber : .spatialCyan)
                                .padding(.top, 4)
                        }

                        // Hand off to semantic room twin view
                        if let roomID {
                            Button {
                                coordinator.dismissFullScreen()
                                coordinator.push(.roomTwin(roomID: roomID))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "cube.transparent")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("View in Room Twin")
                                        .font(SpatialFont.caption)
                                }
                                .foregroundStyle(.spatialCyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.spatialCyan.opacity(0.08), in: Capsule())
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.elevatedSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Floating query bar
                FloatingQueryBar(onSubmit: { query in
                    Task {
                        await viewModel.executeSearch(
                            query: query,
                            roomID: roomID,
                            modelContext: modelContext,
                            backendClient: backendClient
                        )
                    }
                })
                .padding(.bottom, 16)
            }
        }
        .task(id: roomID) {
            startSession()
            viewModel.setInitialRouteTarget(initialRouteTarget)
            await backendClient.checkConnection()
        }
        .onChange(of: sessionManager.trackingState) { _, trackingState in
            relocMonitor.update(
                trackingState: trackingState,
                mappingStatus: sessionManager.worldMappingStatus
            )
        }
        .onChange(of: sessionManager.worldMappingStatus) { _, mappingStatus in
            relocMonitor.update(
                trackingState: sessionManager.trackingState,
                mappingStatus: mappingStatus
            )
        }
        .onDisappear {
            viewModel.clearOverlays(in: nil)
            relocMonitor.reset()
            sessionManager.pause()
        }
    }

    private var trackingQuality: TrackingQuality {
        switch sessionManager.trackingState {
        case .notAvailable:
            return .notAvailable
        case .limited:
            return .limited
        case .normal:
            return .normal
        }
    }

    private func startSession() {
        let persistence = RoomPersistenceService()
        guard let roomID, persistence.worldMapExists(for: roomID) else {
            relocMonitor.reset()
            sessionManager.startWorldTracking()
            return
        }

        let worldMapURL = persistence.worldMapURL(for: roomID)
        if let worldMap = try? WorldMapStore.load(from: worldMapURL) {
            sessionManager.startWorldTracking(initialWorldMap: worldMap)
            relocMonitor.bind(to: sessionManager)
        } else {
            relocMonitor.reset()
            sessionManager.startWorldTracking()
        }
    }
}
