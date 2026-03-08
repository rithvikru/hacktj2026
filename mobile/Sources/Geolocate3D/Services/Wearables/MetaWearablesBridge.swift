import Foundation
import UIKit

#if canImport(MWDATCore)
import MWDATCore
#endif

#if canImport(MWDATCamera)
import MWDATCamera
#endif

enum WearablesBridgeError: LocalizedError {
    case sdkUnavailable
    case registrationFailed
    case streamUnavailable
    case cameraPermissionDenied

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Meta DAT SDK is unavailable in this build."
        case .registrationFailed:
            return "Meta wearable registration did not complete successfully."
        case .streamUnavailable:
            return "Meta DAT camera streaming is unavailable."
        case .cameraPermissionDenied:
            return "Camera permission on Meta glasses was denied. Grant access in the Meta AI app."
        }
    }
}

@MainActor
final class MetaWearablesBridge: WearablesBridge {
    private(set) var registrationState: WearableRegistrationState = .unconfigured
    private(set) var streamState: WearableStreamState = .idle

    private var stateListeners: [Any] = []
    private var frameListeners: [Any] = []

    #if canImport(MWDATCamera)
    private var streamSession: StreamSession?
    #endif

    func configure() throws {
        #if canImport(MWDATCore)
        do {
            try Wearables.configure()
            registrationState = .configured
            NSLog("[MWDAT] configure() OK")
        } catch {
            let msg = "configure: \(String(describing: error))"
            NSLog("[MWDAT] %@", msg)
            registrationState = .failed(msg)
            throw error
        }
        #else
        registrationState = .failed(WearablesBridgeError.sdkUnavailable.localizedDescription)
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func beginRegistration() async throws {
        #if canImport(MWDATCore)

        if case .failed = registrationState {
            try configure()
        }
        if case .unconfigured = registrationState {
            try configure()
        }

        registrationState = .registering
        let sdkState = Wearables.shared.registrationState
        NSLog("[MWDAT] startRegistration — SDK state=%@", String(describing: sdkState))
        do {
            try await Wearables.shared.startRegistration()
            registrationState = .registered
            NSLog("[MWDAT] startRegistration OK")
        } catch {
            let msg = "register: \(String(describing: error))"
            NSLog("[MWDAT] %@", msg)
            registrationState = .failed(msg)
            throw error
        }
        #else
        registrationState = .failed(WearablesBridgeError.sdkUnavailable.localizedDescription)
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func handleOpenURL(_ url: URL) async throws -> Bool {
        #if canImport(MWDATCore)
        do {
            let result = try await Wearables.shared.handleUrl(url)
            registrationState = .registered
            return result
        } catch {
            registrationState = .failed(error.localizedDescription)
            throw error
        }
        #else
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func startStreaming(
        onFrame: @escaping @Sendable (WearableCapturedFrame) -> Void,
        onStateChange: @escaping @Sendable (WearableStreamState) -> Void
    ) async throws {
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        streamState = .connecting
        onStateChange(.connecting)

        let wearables = Wearables.shared
        let cameraStatus = try await wearables.checkPermissionStatus(.camera)
        if cameraStatus == .denied {
            let requested = try await wearables.requestPermission(.camera)
            if requested == .denied {
                streamState = .failed(WearablesBridgeError.cameraPermissionDenied.localizedDescription)
                onStateChange(streamState)
                throw WearablesBridgeError.cameraPermissionDenied
            }
        }

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        streamSession = session

        let stateToken = session.statePublisher.listen { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                let mappedState = self.mapVendorState(String(describing: state))
                self.streamState = mappedState
                onStateChange(mappedState)
            }
        }
        stateListeners.append(stateToken)

        let frameToken = session.videoFramePublisher.listen { frame in
            guard let image = frame.makeUIImage() else { return }
            let captured = WearableCapturedFrame(
                image: image,
                placeHint: nil,
                observedObjects: [],
                sampleReason: "wearable_stream",
                width: Int(image.size.width),
                height: Int(image.size.height)
            )
            onFrame(captured)
        }
        frameListeners.append(frameToken)

        await session.start()
        streamState = .streaming
        onStateChange(.streaming)
        #else
        streamState = .failed(WearablesBridgeError.streamUnavailable.localizedDescription)
        onStateChange(streamState)
        throw WearablesBridgeError.streamUnavailable
        #endif
    }

    func stopStreaming() async {
        #if canImport(MWDATCamera)
        await streamSession?.stop()
        streamSession = nil
        #endif
        stateListeners.removeAll()
        frameListeners.removeAll()
        streamState = .stopped
    }

    private func mapVendorState(_ description: String) -> WearableStreamState {
        let normalized = description.lowercased()
        if normalized.contains("stream") {
            return .streaming
        }
        if normalized.contains("reconnect") {
            return .reconnecting
        }
        if normalized.contains("degrad") {
            return .degraded
        }
        if normalized.contains("pause") {
            return .paused
        }
        if normalized.contains("connect") {
            return .connecting
        }
        if normalized.contains("stop") {
            return .stopped
        }
        return .idle
    }
}
