import ARKit
import RealityKit

final class ARViewCoordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    private let sessionManager: SpatialSessionManager
    private let viewModel: LiveSearchViewModel

    init(sessionManager: SpatialSessionManager, viewModel: LiveSearchViewModel) {
        self.sessionManager = sessionManager
        self.viewModel = viewModel
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self, let arView = self.arView else { return }

            self.sessionManager.trackingState = frame.camera.trackingState
            self.sessionManager.worldMappingStatus = frame.worldMappingStatus

            self.viewModel.syncOverlays(in: arView)
            self.viewModel.updateScreenProjections(arView: arView)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {

    }
}
