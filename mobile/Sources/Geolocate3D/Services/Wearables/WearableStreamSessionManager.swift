import Foundation
import Observation

@Observable
@MainActor
final class WearableStreamSessionManager {
    var registrationState: WearableRegistrationState = .unconfigured
    var streamState: WearableStreamState = .idle
    var activeSessionID: String?
    var activeHomeID: String?
    var acceptedFrameCount = 0
    var lastErrorMessage: String?

    private let bridge: WearablesBridge
    private let persistence = WearablePersistenceService()
    private var sampler = WearableFrameSampler(targetFPS: 1.0)
    private weak var backendClient: BackendClient?

    init(bridge: WearablesBridge = MetaWearablesBridge()) {
        self.bridge = bridge
    }

    func attachBackendClient(_ backendClient: BackendClient) {
        self.backendClient = backendClient
    }

    func configureIfNeeded() {
        guard case .unconfigured = registrationState else { return }
        do {
            try bridge.configure()
            registrationState = bridge.registrationState
        } catch {
            registrationState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func beginRegistration() {
        do {
            try bridge.beginRegistration()
            registrationState = bridge.registrationState
        } catch {
            registrationState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleOpenURL(_ url: URL) async {
        do {
            _ = try await bridge.handleOpenURL(url)
            registrationState = bridge.registrationState
        } catch {
            lastErrorMessage = error.localizedDescription
            registrationState = .failed(error.localizedDescription)
        }
    }

    func startStreaming(homeID: String, placeHint: String? = nil) async {
        guard let backendClient else {
            lastErrorMessage = "Backend client is not attached."
            return
        }

        configureIfNeeded()
        if case .failed(let message) = registrationState {
            lastErrorMessage = message
            return
        }

        do {
            let sessionID = try await backendClient.createWearableSession(
                homeID: homeID,
                deviceName: "Ray-Ban Meta",
                source: "rayban_meta",
                samplingFPS: sampler.targetFPS
            )
            activeSessionID = sessionID
            activeHomeID = homeID
            try await bridge.startStreaming(
                onFrame: { [weak self] frame in
                    Task { @MainActor in
                        await self?.handleCapturedFrame(frame, forcedPlaceHint: placeHint)
                    }
                },
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        self?.streamState = state
                    }
                }
            )
        } catch {
            streamState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopStreaming() async {
        await bridge.stopStreaming()
        streamState = .stopped
    }

    private func handleCapturedFrame(_ frame: WearableCapturedFrame, forcedPlaceHint: String?) async {
        guard let backendClient, let sessionID = activeSessionID, let homeID = activeHomeID else { return }
        guard sampler.shouldSample(at: frame.timestamp, reason: frame.sampleReason) else { return }

        do {
            let persisted = try persistence.saveFrameImage(frame.image, sessionID: sessionID, frameID: frame.id)
            let upload = WearableFrameUpload(
                frameID: frame.id.uuidString,
                timestamp: ISO8601DateFormatter().string(from: frame.timestamp),
                sampleReason: frame.sampleReason,
                placeHint: forcedPlaceHint ?? frame.placeHint,
                observedObjects: frame.observedObjects,
                imageJPEGBase64: persisted.imageBase64,
                imageWidth: frame.width,
                imageHeight: frame.height,
                metadata: [
                    "local_image_path": persisted.imagePath,
                    "capture_source": "rayban_meta",
                ]
            )
            try await backendClient.uploadWearableFrames(sessionID: sessionID, frames: [upload])
            acceptedFrameCount += 1
            if acceptedFrameCount % 5 == 0 {
                _ = try await backendClient.rebuildTopology(homeID: homeID)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            streamState = .failed(error.localizedDescription)
        }
    }
}
