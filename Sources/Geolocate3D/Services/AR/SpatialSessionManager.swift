import ARKit
import Combine

@Observable
@MainActor
final class SpatialSessionManager: NSObject, ARSessionDelegate {
    private(set) var session: ARSession?
    var trackingState: ARCamera.TrackingState = .notAvailable
    var isRunning = false
    var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable

    func startWorldTracking(initialWorldMap: ARWorldMap? = nil) {
        let arSession: ARSession
        if let existing = session {
            arSession = existing
        } else {
            arSession = ARSession()
            arSession.delegate = self
            session = arSession
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if let map = initialWorldMap {
            config.initialWorldMap = map
        }

        arSession.run(config, options: initialWorldMap == nil
            ? [.resetTracking, .removeExistingAnchors]
            : [])
        isRunning = true
    }

    func pause() {
        session?.pause()
        session?.delegate = nil
        session = nil
        isRunning = false
    }

    func tearDown() {
        session?.pause()
        session?.delegate = nil
        session = nil
        isRunning = false
        trackingState = .notAvailable
        worldMappingStatus = .notAvailable
    }

    func getCurrentWorldMap() async throws -> ARWorldMap {
        guard let session else {
            throw ARError(.sessionFailed)
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map { continuation.resume(returning: map) }
                else { continuation.resume(throwing: error ?? ARError(.sessionFailed)) }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            trackingState = frame.camera.trackingState
            worldMappingStatus = frame.worldMappingStatus
        }
    }
}
