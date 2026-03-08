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

    var connectedDeviceName: String?
    var connectedDeviceType: String?

    var onFrameAccepted: ((WearableCapturedFrame, String) -> Void)?

    private var bridge: WearablesBridge
    private let persistence = WearablePersistenceService()
    private var sampler = WearableFrameSampler(targetFPS: 1.0)
    private weak var backendClient: BackendClient?

    private var bridgeStateSyncTask: Task<Void, Never>?

    private var consecutiveUploadFailures = 0
    private let maxConsecutiveUploadFailures = 5

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
        bridgeStateSyncTask?.cancel()
        bridgeStateSyncTask = nil
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
        connectedDeviceName = nil
        connectedDeviceType = nil
        onFrameAccepted = nil
    }

    func configureIfNeeded() {
        guard case .unconfigured = registrationState else { return }
        do {
            try bridge.configure()
            syncBridgeState()
            startBridgeStateSync()
        } catch {
            registrationState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func beginRegistration() async {

        if case .unconfigured = registrationState {
            configureIfNeeded()
        }
        if case .failed = registrationState {

            registrationState = .unconfigured
            configureIfNeeded()
        }

        if case .failed = registrationState {
            return
        }
        do {
            try await bridge.beginRegistration()
            syncBridgeState()

            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                syncBridgeState()
                if case .registered = registrationState { break }
            }
        } catch {
            registrationState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleOpenURL(_ url: URL) async {
        do {
            _ = try await bridge.handleOpenURL(url)
            syncBridgeState()
            lastErrorMessage = nil
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

        if case .registrationRequired = registrationState {
            await beginRegistration()
            if case .failed(let message) = registrationState {
                lastErrorMessage = message
                return
            }
        }

        consecutiveUploadFailures = 0

        do {
            let session = try await backendClient.createWearableSession(
                homeID: homeID,
                deviceName: connectedDeviceName ?? "Ray-Ban Meta",
                source: "rayban_meta",
                samplingFPS: sampler.targetFPS
            )
            activeSessionID = session.sessionID
            let summary = try persistence.initializeSessionSummary(
                sessionID: session.sessionID,
                homeID: homeID,
                deviceName: session.deviceName ?? connectedDeviceName ?? "Ray-Ban Meta"
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

    func syncBridgeState() {
        registrationState = bridge.registrationState
        streamState = bridge.streamState
        if let metaBridge = bridge as? MetaWearablesBridge {
            connectedDeviceName = metaBridge.connectedDeviceName
            connectedDeviceType = metaBridge.connectedDeviceType
        }
    }

    private func startBridgeStateSync() {
        bridgeStateSyncTask?.cancel()
        bridgeStateSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.syncBridgeState()
            }
        }
    }

    private func handleCapturedFrame(_ frame: WearableCapturedFrame, forcedPlaceHint: String?) async {
        guard let backendClient, let sessionID = activeSessionID, let homeID = activeHomeID else { return }
        guard sampler.shouldSample(at: frame.timestamp, reason: frame.sampleReason) else { return }

        let persisted: PersistedWearableFrame
        do {
            persisted = try persistence.saveFrameImage(frame.image, sessionID: sessionID, frameID: frame.id)
            let localSummary = try persistence.recordFrame(
                sessionID: sessionID,
                frameID: frame.id,
                timestamp: frame.timestamp
            )
            localPersistedFrameCount = localSummary.localFrameCount
            latestSessionStoragePath = localSummary.sessionDirectoryPath
        } catch {
            NSLog("[WearableStream] Local persist failed (non-fatal): %@", error.localizedDescription)

            onFrameAccepted?(frame, sessionID)
            return
        }

        onFrameAccepted?(frame, sessionID)

        do {
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
            consecutiveUploadFailures = 0
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
                _ = try? await backendClient.rebuildTopology(homeID: homeID)
            }
        } catch {
            consecutiveUploadFailures += 1
            NSLog("[WearableStream] Upload failed (%d/%d): %@",
                  consecutiveUploadFailures, maxConsecutiveUploadFailures,
                  error.localizedDescription)
            lastErrorMessage = "Upload failed (\(consecutiveUploadFailures)x): \(error.localizedDescription)"

            if consecutiveUploadFailures >= maxConsecutiveUploadFailures {
                NSLog("[WearableStream] Too many consecutive upload failures — stopping stream")
                _ = try? await backendClient.updateWearableSessionStatus(sessionID: sessionID, status: "failed")
                streamState = .failed("Backend unreachable after \(maxConsecutiveUploadFailures) attempts")
            } else {

                streamState = .degraded
            }
        }
    }

    var isStreamingActive: Bool {
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
