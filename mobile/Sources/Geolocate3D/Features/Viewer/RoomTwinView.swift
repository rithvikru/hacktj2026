import SwiftUI
import SceneKit
import SwiftData
import WebKit

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
            if viewModel.viewerMode == .dense, let denseURL = viewModel.denseAssetRemoteURL, viewModel.shouldUsePhotorealDenseViewer {
                SplatWebViewRepresentable(sceneURL: denseURL)
                    .ignoresSafeArea()
            } else {
                // SceneKit semantic/structure view with built-in camera control
                SceneViewRepresentable(
                    roomID: roomID,
                    observations: viewModel.observations,
                    hypotheses: viewModel.hypotheses,
                    showScaffold: viewModel.showScaffold,
                    showObjects: viewModel.showObjects,
                    showHeatmap: viewModel.showHeatmap,
                    showDense: viewModel.showDense,
                    denseAssetURL: viewModel.denseAssetURL,
                    semanticObjects: viewModel.semanticObjects,
                    semanticMeshLocalURLs: viewModel.semanticMeshLocalURLs,
                    selectedSemanticObjectID: viewModel.selectedSemanticObjectID,
                    showSemanticObjects: viewModel.showSemanticObjects,
                    viewerMode: viewModel.viewerMode,
                    onSemanticObjectTapped: { objectID in
                        if objectID.isEmpty {
                            viewModel.deselectSemanticObject()
                        } else {
                            viewModel.selectSemanticObject(id: objectID)
                        }
                    },
                    projectedPositions: $projectedPositions
                )
                .ignoresSafeArea()
            }

            // SwiftUI annotation overlays — only for selected object and nearby
            if viewModel.showObjects {
                ForEach(filteredObservationsForPins) { obs in
                    if let screenPos = projectedPositions[obs.id] {
                        AnnotationPin(
                            observation: obs,
                            isSelected: false,
                            showLabel: viewModel.showLabels || viewModel.selectedSemanticObjectID != nil
                        )
                        .position(screenPos)
                        .onTapGesture {
                            coordinator.presentSheet(.objectDetail(observationID: obs.id))
                        }
                    }
                }
            }

            // Status + Layer controls
            VStack {
                // Status pill
                if let statusText = effectiveStatusLine {
                    HStack(spacing: 8) {
                        if isFailureStatus {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.warningAmber)
                                .font(.system(size: 13))
                        } else if isSuccessStatus {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.confirmGreen)
                                .font(.system(size: 13))
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.spatialCyan)
                        }
                        Text(statusText)
                            .font(SpatialFont.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.elevatedSurface.opacity(0.9), in: Capsule())
                    .padding(.top, 12)
                }

                Spacer()

                // Semantic object selection info card
                if let selectedObj = viewModel.selectedSemanticObject {
                    SemanticObjectInfoCard(
                        object: selectedObj,
                        onLocateInAR: {
                            coordinator.presentImmersive(.liveSearch(roomID: roomID))
                        },
                        onDismiss: {
                            viewModel.deselectSemanticObject()
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Mode-first layer toggle bar
                LayerToggleBar(
                    viewerMode: $viewModel.viewerMode,
                    showLabels: $viewModel.showLabels,
                    showSearchHits: $viewModel.showSearchHits,
                    showHypotheses: $viewModel.showHypothesesOverlay,
                    onModeChanged: { mode in
                        viewModel.applyViewerMode(mode)
                    }
                )
                .padding(.bottom, 20)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.selectedSemanticObjectID)
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
                    Button("Refresh Assets", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refreshAssets(
                                modelContext: modelContext,
                                backendClient: backendClient
                            )
                            await viewModel.loadSemanticScene(
                                roomID: roomID,
                                backendClient: backendClient
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.spatialCyan)
                }
            }
        }
        .task {
            await viewModel.loadRoom(
                modelContext: modelContext,
                backendClient: backendClient
            )
        }
        .onChange(of: viewModel.viewerMode) { _, mode in
            if mode == .dense, viewModel.denseAssetURL == nil {
                Task {
                    await viewModel.refreshAssets(
                        modelContext: modelContext,
                        backendClient: backendClient
                    )
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Only show annotation pins for selected object's nearby observations, not everything.
    private var filteredObservationsForPins: [ObjectObservation] {
        guard let selectedObj = viewModel.selectedSemanticObject else {
            // If no semantic selection, show all observations when labels enabled
            if viewModel.showLabels {
                return viewModel.observations
            }
            return []
        }

        // Show observations near the selected semantic object
        guard let center = selectedObj.centerXYZ, center.count == 3 else {
            return []
        }
        let selectedPosition = SIMD3<Float>(center[0], center[1], center[2])
        let proximityThreshold: Float = 1.5

        return viewModel.observations.filter { obs in
            let obsPos = SIMD3<Float>(
                obs.worldTransform.columns.3.x,
                obs.worldTransform.columns.3.y,
                obs.worldTransform.columns.3.z
            )
            return simd_distance(obsPos, selectedPosition) < proximityThreshold
        }
    }

    private var effectiveStatusLine: String? {
        if let statusMessage = viewModel.statusMessage {
            return statusMessage
        }
        switch viewModel.reconstructionStatus {
        case .pending:
            if !viewModel.semanticObjects.isEmpty {
                return nil // Semantic ready, no need to show pending
            }
            return "Preparing room geometry"
        case .uploading:
            return "Uploading scan assets for reconstruction"
        case .processing:
            return "Building room representation"
        case .complete:
            if viewModel.viewerMode == .dense && !viewModel.shouldUsePhotorealDenseViewer {
                return "Dense mode needs a real splat asset; showing semantic room twin"
            }
            return nil // All good, hide status
        case .failed:
            if !viewModel.semanticObjects.isEmpty {
                return "Semantic room preview ready"
            }
            return "Dense reconstruction failed"
        }
    }

    private var isFailureStatus: Bool {
        viewModel.reconstructionStatus == .failed && viewModel.semanticObjects.isEmpty
    }

    private var isSuccessStatus: Bool {
        guard let msg = effectiveStatusLine else { return false }
        return msg.contains("ready")
    }
}

private struct SplatWebViewRepresentable: UIViewRepresentable {
    let sceneURL: URL

    final class Coordinator {
        var lastSceneURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(Self.html(sceneURL: sceneURL), baseURL: nil)
        context.coordinator.lastSceneURL = sceneURL
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastSceneURL != sceneURL else { return }
        context.coordinator.lastSceneURL = sceneURL
        webView.loadHTMLString(Self.html(sceneURL: sceneURL), baseURL: nil)
    }

    private static func html(sceneURL: URL) -> String {
        let escapedURL = sceneURL.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
            <style>
              html, body, #viewer { margin: 0; width: 100%; height: 100%; background: #05070a; overflow: hidden; }
              #loading {
                position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
                color: white; font: 600 16px -apple-system, BlinkMacSystemFont, sans-serif; letter-spacing: 0.02em;
                background: radial-gradient(circle at top, rgba(42, 103, 162, 0.18), transparent 45%), #05070a;
              }
              #error {
                position: absolute; left: 16px; right: 16px; bottom: 20px; padding: 12px 14px; border-radius: 14px;
                color: #ffd6d6; background: rgba(66, 11, 18, 0.82); font: 500 14px -apple-system, BlinkMacSystemFont, sans-serif;
                display: none;
              }
            </style>
          </head>
          <body>
            <div id="viewer"></div>
            <div id="loading">Loading room twin…</div>
            <div id="error"></div>
            <script type="module">
              import * as GaussianSplats3D from 'https://esm.sh/@mkkellogg/gaussian-splats-3d';

              const sceneURL = "\(escapedURL)";
              const loading = document.getElementById('loading');
              const errorView = document.getElementById('error');

              const showError = (message) => {
                loading.style.display = 'none';
                errorView.style.display = 'block';
                errorView.textContent = message;
              };

              try {
                const viewer = new GaussianSplats3D.Viewer({
                  'rootElement': document.getElementById('viewer'),
                  'cameraUp': [0, 1, 0],
                  'initialCameraPosition': [0, 1.6, 3.6],
                  'initialCameraLookAt': [0, 1.2, 0],
                  'sharedMemoryForWorkers': false,
                  'progressiveLoad': true,
                  'showLoadingUI': false,
                });

                await viewer.addSplatScene(sceneURL, {
                  'progressiveLoad': true,
                  'showLoadingUI': false,
                  'splatAlphaRemovalThreshold': 4
                });
                viewer.start();
                loading.style.display = 'none';
              } catch (error) {
                showError(`Dense room twin failed to load: ${error?.message ?? error}`);
              }
            </script>
          </body>
        </html>
        """
    }
}

// MARK: - Semantic Object Info Card

private struct SemanticObjectInfoCard: View {
    let object: SemanticSceneObject
    let onLocateInAR: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(object.label.capitalized)
                        .font(SpatialFont.headline)
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Text("\(Int(object.confidence * 100))% confidence")
                            .font(SpatialFont.dataSmall)
                            .foregroundStyle(confidenceColor.opacity(0.9))

                        if let supportRelation = object.supportRelation,
                           !supportRelation.displayDescription.isEmpty {
                            Text(supportRelation.displayDescription)
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                        }
                    }
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.dimLabel)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 8) {
                InfoCardButton(title: "Locate in AR", icon: "arkit") {
                    onLocateInAR()
                }
                InfoCardButton(title: "Evidence", icon: "photo.stack") {
                    // Evidence viewer — future feature
                }
                InfoCardButton(title: "Details", icon: "info.circle") {
                    // Detail sheet — future feature
                }
            }
        }
        .padding(14)
        .background(Color.elevatedSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.spatialCyan.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var confidenceColor: Color {
        if object.confidence >= 0.8 { return .confirmGreen }
        if object.confidence >= 0.5 { return .spatialCyan }
        if object.confidence >= 0.3 { return .warningAmber }
        return .dimLabel
    }
}

private struct InfoCardButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(SpatialFont.caption)
            }
            .foregroundStyle(.spatialCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.spatialCyan.opacity(0.08), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.spatialCyan.opacity(0.15), lineWidth: 0.5)
            )
        }
    }
}
