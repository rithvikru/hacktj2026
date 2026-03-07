@preconcurrency import ARKit
import Combine

/// Singleton AR session manager.
/// Fix 4 applied: session is lazy/optional to avoid conflicting with RoomCaptureView's
/// internal ARSession. Only one ARSession can be active per process on iOS.
@Observable
@MainActor
final class SpatialSessionManager: NSObject, ARSessionDelegate {
    private(set) var session: ARSession?
    var trackingState: ARCamera.TrackingState = .notAvailable
    var isRunning = false
    var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable

    // MARK: - Session Lifecycle

    /// Creates and starts a world tracking session.
    /// Call only when no other ARSession (e.g. RoomCaptureView) is active.
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

    /// Pauses and nils the session to free resources.
    /// Must be called before RoomCaptureView starts its own ARSession.
    func pause() {
        session?.pause()
        session?.delegate = nil
        session = nil
        isRunning = false
    }

    /// Fully tears down the session so RoomCaptureView can own its own ARSession.
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
            throw ARError(.worldTrackingFailed)
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map { continuation.resume(returning: map) }
                else { continuation.resume(throwing: error ?? ARError(.worldTrackingFailed)) }
            }
        }
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            trackingState = frame.camera.trackingState
            worldMappingStatus = frame.worldMappingStatus
        }
    }
}
