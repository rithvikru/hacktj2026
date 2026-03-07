import SwiftUI
import RealityKit
import ARKit

struct LiveSearchView: View {
    let roomID: UUID?
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SpatialSessionManager.self) private var sessionManager
    @State private var viewModel = LiveSearchViewModel()
    @State private var relocMonitor = RelocalizationMonitor()

    var body: some View {
        ZStack {

            ARViewRepresentable(viewModel: viewModel, sessionManager: sessionManager)
                .ignoresSafeArea()

            ForEach(viewModel.screenProjectedObservations) { obs in
                ObjectTooltipOverlay(observation: obs)
                    .position(x: obs.screenX, y: obs.screenY - 40)
            }

            VStack {

                HStack {
                    Button { coordinator.dismissFullScreen() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    TrackingStatusBadge(quality: trackingQuality)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                if relocMonitor.state == .relocalizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.spatialCyan)
                        Text(relocMonitor.statusMessage)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                } else if relocMonitor.state == .failed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.warningAmber)
                        Text(relocMonitor.statusMessage)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.warningAmber)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                }

                Spacer()

                if !viewModel.activeObservations.isEmpty {
                    HStack {
                        Text("\(viewModel.activeObservations.count)")
                            .font(SpatialFont.dataLarge)
                            .foregroundStyle(.spatialCyan)
                        Text("objects detected")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                }

                FloatingQueryBar(onSubmit: { query in
                    Task { await viewModel.executeSearch(query: query) }
                })
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            sessionManager.startWorldTracking()
            relocMonitor.bind(to: sessionManager)
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
}
