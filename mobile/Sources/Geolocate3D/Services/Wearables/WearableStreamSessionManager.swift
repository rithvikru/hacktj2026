import Foundation
import Observation

@Observable
@MainActor
final class WearableStreamSessionManager {
    var bridgeMode: WearableBridgeMode
    var registrationState: WearableRegistrationState = .unconfigured
    var streamState: WearableStreamState = .idle
    var activeSessionID: String?
    var activeHomeID: String?
    var acceptedFrameCount = 0
    var localPersistedFrameCount = 0
    var backendFrameCount = 0
    var latestSessionStoragePath: String?
    var latestBackendSessionStatus: String?
    var lastErrorMessage: String?

    private var bridge: WearablesBridge
    private let persistence = WearablePersistenceService()
    private var sampler = WearableFrameSampler(targetFPS: 1.0)
    private weak var backendClient: BackendClient?

    init(bridgeMode: WearableBridgeMode = .meta) {
        self.bridgeMode = bridgeMode
        self.bridge = Self.makeBridge(for: bridgeMode)
    }

    func attachBackendClient(_ backendClient: BackendClient) {
        self.backendClient = backendClient
    }

    func setBridgeMode(_ mode: WearableBridgeMode) {
        guard mode != bridgeMode else { return }
        guard !isStreamingActive else {
            lastErrorMessage = "Stop streaming before switching wearable mode."
            return
        }
        bridgeMode = mode
        bridge = Self.makeBridge(for: mode)
        registrationState = .unconfigured
        streamState = .idle
        activeSessionID = nil
        acceptedFrameCount = 0
        localPersistedFrameCount = 0
        backendFrameCount = 0
        latestSessionStoragePath = nil
        latestBackendSessionStatus = nil
        lastErrorMessage = nil
    }

    func configureIfNeeded() {
        guard case .unconfigured = registrationState else { return }
        do {
            try bridge.configure()
            registrationState = bridge.registrationState
        } catch {
            let detail = "\(String(describing: error)) | \(error.localizedDescription)"
            registrationState = .failed(detail)
            lastErrorMessage = detail
        }
    }

    func beginRegistration() async {
        do {
            try await bridge.beginRegistration()
            registrationState = bridge.registrationState
        } catch {
            let detail = "\(String(describing: error)) | \(error.localizedDescription)"
            registrationState = .failed(detail)
            lastErrorMessage = detail
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
        lastErrorMessage = nil

        configureIfNeeded()
        if case .failed(let message) = registrationState {
            lastErrorMessage = message
            return
        }

        do {
            let session = try await backendClient.createWearableSession(
                homeID: homeID,
                deviceName: "Ray-Ban Meta",
                source: "rayban_meta",
                samplingFPS: sampler.targetFPS
            )
            activeSessionID = session.sessionID
            let summary = try persistence.initializeSessionSummary(
                sessionID: session.sessionID,
                homeID: homeID,
                deviceName: session.deviceName ?? "Ray-Ban Meta"
            )
            activeHomeID = homeID
            acceptedFrameCount = session.frameCount
            backendFrameCount = session.frameCount
            localPersistedFrameCount = summary.localFrameCount
            latestSessionStoragePath = summary.sessionDirectoryPath
            latestBackendSessionStatus = session.status
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
            if let sessionID = activeSessionID {
                _ = try? await backendClient.updateWearableSessionStatus(sessionID: sessionID, status: "failed")
            }
            streamState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopStreaming() async {
        await bridge.stopStreaming()
        if let backendClient, let sessionID = activeSessionID {
            if let response = try? await backendClient.updateWearableSessionStatus(sessionID: sessionID, status: "stopped") {
                latestBackendSessionStatus = response.status
                backendFrameCount = response.frameCount
                acceptedFrameCount = response.frameCount
            }
        }
        streamState = .stopped
    }

    func refreshActiveSession() async {
        guard let backendClient, let sessionID = activeSessionID else { return }
        do {
            let session = try await backendClient.fetchWearableSession(sessionID: sessionID)
            backendFrameCount = session.frameCount
            acceptedFrameCount = session.frameCount
            latestBackendSessionStatus = session.status
            if let summary = try? persistence.syncBackendFrameCount(
                sessionID: sessionID,
                backendFrameCount: session.frameCount
            ) {
                localPersistedFrameCount = summary.localFrameCount
                latestSessionStoragePath = summary.sessionDirectoryPath
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleCapturedFrame(_ frame: WearableCapturedFrame, forcedPlaceHint: String?) async {
        guard let backendClient, let sessionID = activeSessionID, let homeID = activeHomeID else { return }
        guard sampler.shouldSample(at: frame.timestamp, reason: frame.sampleReason) else { return }

        do {
            let persisted = try persistence.saveFrameImage(frame.image, sessionID: sessionID, frameID: frame.id)
            let localSummary = try persistence.recordFrame(
                sessionID: sessionID,
                frameID: frame.id,
                timestamp: frame.timestamp
            )
            localPersistedFrameCount = localSummary.localFrameCount
            latestSessionStoragePath = localSummary.sessionDirectoryPath
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
            let response = try await backendClient.uploadWearableFrames(sessionID: sessionID, frames: [upload])
            acceptedFrameCount = response.frameCount
            backendFrameCount = response.frameCount
            latestBackendSessionStatus = response.status
            if let summary = try? persistence.syncBackendFrameCount(
                sessionID: sessionID,
                backendFrameCount: response.frameCount
            ) {
                localPersistedFrameCount = summary.localFrameCount
            }
            if acceptedFrameCount % 5 == 0 {
                _ = try await backendClient.rebuildTopology(homeID: homeID)
            }
        } catch {
            if let sessionID = activeSessionID {
                _ = try? await backendClient.updateWearableSessionStatus(sessionID: sessionID, status: "failed")
            }
            lastErrorMessage = error.localizedDescription
            streamState = .failed(error.localizedDescription)
        }
    }

    private var isStreamingActive: Bool {
        switch streamState {
        case .connecting, .streaming, .degraded, .reconnecting, .paused:
            return true
        default:
            return false
        }
    }

    private static func makeBridge(for mode: WearableBridgeMode) -> WearablesBridge {
        switch mode {
        case .meta:
            return MetaWearablesBridge()
        case .simulated:
            return SimulatedWearablesBridge()
        }
    }
}
