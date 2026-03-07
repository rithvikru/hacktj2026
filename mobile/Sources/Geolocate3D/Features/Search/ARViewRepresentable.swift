import SwiftUI
import RealityKit
import ARKit

struct ARViewRepresentable: UIViewRepresentable {
    let viewModel: LiveSearchViewModel
    let sessionManager: SpatialSessionManager

    func makeCoordinator() -> ARViewCoordinator {
        ARViewCoordinator(sessionManager: sessionManager, viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        if let session = sessionManager.session {
            arView.session = session
            arView.session.delegate = context.coordinator
        }

        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        arView.environment.background = .cameraFeed()

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {

        if let session = sessionManager.session, arView.session !== session {
            arView.session = session
            arView.session.delegate = context.coordinator
        }
        context.coordinator.arView = arView
    }
}
