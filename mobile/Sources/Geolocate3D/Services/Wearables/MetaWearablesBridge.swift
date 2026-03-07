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

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Meta DAT SDK is unavailable in this build."
        case .registrationFailed:
            return "Meta wearable registration did not complete successfully."
        case .streamUnavailable:
            return "Meta DAT camera streaming is unavailable."
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
        try Wearables.configure()
        registrationState = .configured
        #else
        registrationState = .failed(WearablesBridgeError.sdkUnavailable.localizedDescription)
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func beginRegistration() throws {
        #if canImport(MWDATCore)
        registrationState = .registering
        do {
            try Wearables.shared.startRegistration()
        } catch {
            registrationState = .failed(error.localizedDescription)
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
            guard let cgImage = frame.makeCGImage() else { return }
            let image = UIImage(cgImage: cgImage)
            let captured = WearableCapturedFrame(
                image: image,
                placeHint: nil,
                observedObjects: [],
                sampleReason: "wearable_stream",
                width: cgImage.width,
                height: cgImage.height
            )
            onFrame(captured)
        }
        frameListeners.append(frameToken)

        try await session.start()
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
