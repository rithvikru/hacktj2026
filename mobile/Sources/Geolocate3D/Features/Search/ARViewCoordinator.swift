@preconcurrency import ARKit
import RealityKit

/// ARSessionDelegate coordinator for ARViewRepresentable.
/// Forwards frame updates to the view model for screen projection and tracking state.
@MainActor
final class ARViewCoordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    private let sessionManager: SpatialSessionManager
    private let viewModel: LiveSearchViewModel
    private let roomID: UUID?
    private let backendClient: BackendClient

    init(
        sessionManager: SpatialSessionManager,
        viewModel: LiveSearchViewModel,
        roomID: UUID?,
        backendClient: BackendClient
    ) {
        self.sessionManager = sessionManager
        self.viewModel = viewModel
        self.roomID = roomID
        self.backendClient = backendClient
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self, let arView = self.arView else { return }

            // Update tracking state on the session manager
            self.sessionManager.trackingState = frame.camera.trackingState
            self.sessionManager.worldMappingStatus = frame.worldMappingStatus
            self.viewModel.handleCameraTransformUpdate(
                frame.camera.transform,
                roomID: self.roomID,
                backendClient: self.backendClient
            )

            // Sync 3D entities and project to screen space
            self.viewModel.syncOverlays(in: arView)
            self.viewModel.updateScreenProjections(arView: arView)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // Placeholder for handling new anchors (plane detection, object anchors, etc.)
    }
}
