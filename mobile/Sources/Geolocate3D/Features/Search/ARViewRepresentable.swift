import SwiftUI
import RealityKit
import ARKit

/// UIViewRepresentable wrapping RealityKit's ARView for iOS.
/// Fix 1: uses ARView (UIKit) instead of visionOS RealityView.
struct ARViewRepresentable: UIViewRepresentable {
    let viewModel: LiveSearchViewModel
    let sessionManager: SpatialSessionManager

    func makeCoordinator() -> ARViewCoordinator {
        ARViewCoordinator(sessionManager: sessionManager, viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        // Attach the managed session so SpatialSessionManager controls lifecycle
        if let session = sessionManager.session {
            arView.session = session
            arView.session.delegate = context.coordinator
        }

        // Minimal rendering config for performance
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        arView.environment.background = .cameraFeed()

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        // Re-attach session if it was recreated (e.g., after tearDown + restart)
        if let session = sessionManager.session, arView.session !== session {
            arView.session = session
            arView.session.delegate = context.coordinator
        }
        context.coordinator.arView = arView
    }
}
