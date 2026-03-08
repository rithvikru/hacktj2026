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
    case registrationFailed(String)
    case streamUnavailable
    case cameraPermissionDenied
    case noDeviceConnected
    case metaAINotInstalled
    case configurationInvalid
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Meta DAT SDK is unavailable in this build."
        case .registrationFailed(let detail):
            return "Meta wearable registration failed: \(detail)"
        case .streamUnavailable:
            return "Meta DAT camera streaming is unavailable."
        case .cameraPermissionDenied:
            return "Camera permission on Meta glasses was denied. Grant access in the Meta AI app."
        case .noDeviceConnected:
            return "No Meta glasses are connected. Open the Meta AI app and ensure glasses are paired and connected."
        case .metaAINotInstalled:
            return "The Meta AI app is not installed. Install it from the App Store and pair your glasses."
        case .configurationInvalid:
            return "MWDAT SDK configuration is invalid. Check Info.plist MWDAT keys (MetaAppID, ClientToken, AppLinkURLScheme, TeamID)."
        case .networkUnavailable:
            return "Network is unavailable. Check your internet connection and try again."
        }
    }
}

@MainActor
final class MetaWearablesBridge: WearablesBridge {
    private(set) var registrationState: WearableRegistrationState = .unconfigured
    private(set) var streamState: WearableStreamState = .idle

    private(set) var connectedDeviceName: String?
    private(set) var connectedDeviceType: String?

    private var stateListeners: [Any] = []
    private var frameListeners: [Any] = []

    #if canImport(MWDATCore)
    private var registrationStateListener: (any AnyListenerToken)?
    private var devicesListener: (any AnyListenerToken)?
    #endif

    #if canImport(MWDATCamera)
    private var streamSession: StreamSession?
    #endif

    private var isConfigured = false

    func configure() throws {
        #if canImport(MWDATCore)
        guard !isConfigured else {

            syncRegistrationState()
            return
        }
        do {
            try Wearables.configure()
            isConfigured = true
            NSLog("[MWDAT] configure() OK")
        } catch {

            if error == .alreadyConfigured {

                isConfigured = true
                NSLog("[MWDAT] configure() already configured — OK")
            } else {
                let msg = describeConfigureError(error)
                NSLog("[MWDAT] configure failed: %@", msg)
                registrationState = .failed(msg)
                throw error
            }
        }

        startRegistrationStateListener()
        startDevicesListener()
        syncRegistrationState()
        #else
        registrationState = .failed(WearablesBridgeError.sdkUnavailable.localizedDescription)
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func beginRegistration() async throws {
        #if canImport(MWDATCore)

        if !isConfigured {
            try configure()
        }

        let sdkState = Wearables.shared.registrationState
        NSLog("[MWDAT] beginRegistration — SDK registrationState: %@", String(describing: sdkState))

        if sdkState == .registered {
            registrationState = .registered
            NSLog("[MWDAT] already registered — skipping startRegistration()")
            refreshDeviceInfo()
            return
        }

        registrationState = .registering
        do {
            try await Wearables.shared.startRegistration()

            syncRegistrationState()
            NSLog("[MWDAT] startRegistration() returned — SDK state: %@",
                  String(describing: Wearables.shared.registrationState))
        } catch {
            let msg = describeRegistrationError(error)
            NSLog("[MWDAT] startRegistration failed: %@", msg)
            registrationState = .failed(msg)
            throw WearablesBridgeError.registrationFailed(msg)
        }
        #else
        registrationState = .failed(WearablesBridgeError.sdkUnavailable.localizedDescription)
        throw WearablesBridgeError.sdkUnavailable
        #endif
    }

    func handleOpenURL(_ url: URL) async throws -> Bool {
        #if canImport(MWDATCore)
        NSLog("[MWDAT] handleOpenURL: %@", url.absoluteString)
        do {
            let result = try await Wearables.shared.handleUrl(url)
            syncRegistrationState()
            refreshDeviceInfo()
            NSLog("[MWDAT] handleUrl result=%d, SDK state=%@",
                  result ? 1 : 0,
                  String(describing: Wearables.shared.registrationState))
            return result
        } catch {
            let msg = "handleUrl failed: \(String(describing: error))"
            NSLog("[MWDAT] %@", msg)
            registrationState = .failed(msg)
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

        let devices = wearables.devices
        NSLog("[MWDAT] startStreaming — devices: %@", String(describing: devices))
        if let deviceId = devices.first,
           let device = wearables.deviceForIdentifier(deviceId) {
            NSLog("[MWDAT] device '%@' linkState: %@", device.nameOrId(), String(describing: device.linkState))

            if device.linkState == .connected {
                do {
                    let cameraGranted = try await requestCameraPermission(wearables: wearables)
                    if !cameraGranted {
                        NSLog("[MWDAT] camera permission denied — will retry via stream error handler")
                    }
                } catch {
                    NSLog("[MWDAT] camera permission check failed (non-fatal): %@", error.localizedDescription)
                }
            }
        } else {
            NSLog("[MWDAT] no devices yet — AutoDeviceSelector will wait for one")
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
                let mappedState = self.mapStreamSessionState(state)
                self.streamState = mappedState
                onStateChange(mappedState)
                NSLog("[MWDAT] stream state changed: %@", String(describing: state))
            }
        }
        stateListeners.append(stateToken)

        let frameToken = session.videoFramePublisher.listen { frame in
            guard let image = frame.makeUIImage() else {
                NSLog("[MWDAT] frame.makeUIImage() returned nil")
                return
            }
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

        let errorToken = session.errorPublisher.listen { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                let msg = self.describeStreamSessionError(error)
                let isFatal = self.isFatalStreamError(error)
                if isFatal {
                    NSLog("[MWDAT] FATAL stream error: %@", msg)
                    self.streamState = .failed(msg)
                    onStateChange(.failed(msg))
                } else {
                    NSLog("[MWDAT] transient stream error (continuing): %@", msg)
                    self.streamState = .degraded
                    onStateChange(.degraded)
                }
            }
        }
        stateListeners.append(errorToken)

        NSLog("[MWDAT] calling session.start()...")
        await session.start()
        NSLog("[MWDAT] session.start() returned, state: %@", String(describing: session.state))

        let currentState = mapStreamSessionState(session.state)
        streamState = currentState
        onStateChange(currentState)
        #else
        streamState = .failed(WearablesBridgeError.streamUnavailable.localizedDescription)
        onStateChange(streamState)
        throw WearablesBridgeError.streamUnavailable
        #endif
    }

    func stopStreaming() async {
        #if canImport(MWDATCamera)
        NSLog("[MWDAT] stopStreaming")
        await streamSession?.stop()
        streamSession = nil
        #endif
        #if canImport(MWDATCore)

        for token in stateListeners {
            if let t = token as? any AnyListenerToken {
                await t.cancel()
            }
        }
        for token in frameListeners {
            if let t = token as? any AnyListenerToken {
                await t.cancel()
            }
        }
        #endif
        stateListeners.removeAll()
        frameListeners.removeAll()
        streamState = .stopped
    }

    #if canImport(MWDATCore)
    private func startRegistrationStateListener() {
        guard registrationStateListener == nil else { return }
        registrationStateListener = Wearables.shared.addRegistrationStateListener { [weak self] sdkState in
            guard let self else { return }
            Task { @MainActor in
                NSLog("[MWDAT] registrationState changed: %@", String(describing: sdkState))
                self.updateRegistrationState(from: sdkState)
            }
        }
    }

    private func startDevicesListener() {
        guard devicesListener == nil else { return }
        devicesListener = Wearables.shared.addDevicesListener { [weak self] devices in
            guard let self else { return }
            Task { @MainActor in
                NSLog("[MWDAT] devices changed: %@", String(describing: devices))
                self.refreshDeviceInfo()
            }
        }
    }

    private func syncRegistrationState() {
        let sdkState = Wearables.shared.registrationState
        updateRegistrationState(from: sdkState)
    }

    private func updateRegistrationState(from sdkState: RegistrationState) {
        switch sdkState {
        case .unavailable:
            registrationState = .unconfigured
        case .available:

            registrationState = .registrationRequired
        case .registering:
            registrationState = .registering
        case .registered:
            registrationState = .registered
            refreshDeviceInfo()
        @unknown default:
            registrationState = .failed("Unknown SDK registration state")
        }
    }

    private func refreshDeviceInfo() {
        let devices = Wearables.shared.devices
        if let deviceId = devices.first,
           let device = Wearables.shared.deviceForIdentifier(deviceId) {
            connectedDeviceName = device.nameOrId()
            connectedDeviceType = String(describing: device.deviceType())
            NSLog("[MWDAT] device: %@ (%@) link=%@",
                  device.nameOrId(),
                  String(describing: device.deviceType()),
                  String(describing: device.linkState))
        } else {
            connectedDeviceName = nil
            connectedDeviceType = nil
        }
    }

    private func requestCameraPermission(wearables: any WearablesInterface) async throws -> Bool {
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            NSLog("[MWDAT] camera permission status: %@", String(describing: status))
            if status == .granted {
                return true
            }

            let requested = try await wearables.requestPermission(.camera)
            NSLog("[MWDAT] requested camera permission, result: %@", String(describing: requested))
            return requested == .granted
        } catch {

            let msg = describePermissionError(error)
            NSLog("[MWDAT] permission error: %@", msg)
            streamState = .failed(msg)
            throw WearablesBridgeError.registrationFailed(msg)
        }
    }
    #endif

    private func describeConfigureError(_ error: Error) -> String {
        #if canImport(MWDATCore)
        if let wErr = error as? WearablesError {
            switch wErr {
            case .internalError:
                return "MWDAT internal error during configure. Restart the app."
            case .alreadyConfigured:
                return "MWDAT SDK was already configured."
            case .configurationError:
                return WearablesBridgeError.configurationInvalid.localizedDescription
            @unknown default:
                return "MWDAT configure error: \(String(describing: wErr))"
            }
        }
        #endif
        return "Configure error: \(error.localizedDescription)"
    }

    private func describeRegistrationError(_ error: Error) -> String {
        #if canImport(MWDATCore)
        if let rErr = error as? RegistrationError {
            switch rErr {
            case .alreadyRegistered:
                return "Already registered with Meta SDK."
            case .configurationInvalid:
                return WearablesBridgeError.configurationInvalid.localizedDescription
            case .metaAINotInstalled:
                return WearablesBridgeError.metaAINotInstalled.localizedDescription
            case .networkUnavailable:
                return WearablesBridgeError.networkUnavailable.localizedDescription
            case .unknown:
                return "Unknown registration error. Try again."
            @unknown default:
                return "Registration error: \(String(describing: rErr))"
            }
        }
        #endif
        return "Registration error: \(error.localizedDescription)"
    }

    private func describePermissionError(_ error: Error) -> String {
        #if canImport(MWDATCore)
        if let pErr = error as? PermissionError {
            switch pErr {
            case .noDevice:
                return "No Meta glasses found to request camera permission."
            case .noDeviceWithConnection:
                return "Meta glasses are not connected. Reconnect in the Meta AI app."
            case .connectionError:
                return "Connection error while requesting camera permission on glasses."
            case .metaAINotInstalled:
                return WearablesBridgeError.metaAINotInstalled.localizedDescription
            case .requestInProgress:
                return "Permission request already in progress."
            case .requestTimeout:
                return "Permission request timed out. Try again."
            case .internalError:
                return "Internal error while requesting camera permission."
            @unknown default:
                return "Permission error: \(String(describing: pErr))"
            }
        }
        #endif
        return "Permission error: \(error.localizedDescription)"
    }

    #if canImport(MWDATCamera)

    private func isFatalStreamError(_ error: StreamSessionError) -> Bool {
        switch error {
        case .permissionDenied, .hingesClosed, .deviceNotFound, .deviceNotConnected:
            return true
        case .timeout, .videoStreamingError, .audioStreamingError, .internalError:
            return false
        @unknown default:
            return false
        }
    }

    private func mapStreamSessionState(_ state: StreamSessionState) -> WearableStreamState {
        switch state {
        case .stopping:
            return .stopped
        case .stopped:
            return .stopped
        case .waitingForDevice:
            return .connecting
        case .starting:
            return .connecting
        case .streaming:
            return .streaming
        case .paused:
            return .paused
        @unknown default:
            return .idle
        }
    }

    private func describeStreamSessionError(_ error: StreamSessionError) -> String {
        switch error {
        case .internalError:
            return "Internal streaming error."
        case .deviceNotFound(let id):
            return "Device '\(id)' not found for streaming."
        case .deviceNotConnected(let id):
            return "Device '\(id)' not connected for streaming."
        case .timeout:
            return "Streaming connection timed out."
        case .videoStreamingError:
            return "Video streaming error on glasses."
        case .audioStreamingError:
            return "Audio streaming error on glasses."
        case .permissionDenied:
            return WearablesBridgeError.cameraPermissionDenied.localizedDescription
        case .hingesClosed:
            return "Glasses hinges are closed. Open them to stream."
        @unknown default:
            return "Stream error: \(String(describing: error))"
        }
    }
    #endif
}
