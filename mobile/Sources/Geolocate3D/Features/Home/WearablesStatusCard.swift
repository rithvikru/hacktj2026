import SwiftUI

struct WearablesStatusCard: View {
    @Environment(WearableStreamSessionManager.self) private var manager

    var body: some View {
        HStack(spacing: 14) {

            Image(systemName: "eyeglasses")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 48, height: 48)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .if(isStreaming) { view in
                    view.spatialGlow(color: .spatialCyan, cornerRadius: 14, intensity: 0.5)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(deviceTitle)
                        .font(SpatialFont.headline)
                        .foregroundStyle(.white)

                    Text(statusLabel)
                        .font(SpatialFont.caption)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15), in: Capsule())
                }

                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isStreaming {
                Circle()
                    .fill(Color.spatialCyan)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingDot())
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 24)
    }

    private var deviceTitle: String {
        if let name = manager.connectedDeviceName, !name.isEmpty {
            return name
        }
        return "Meta Ray-Bans"
    }

    private var isStreaming: Bool {
        manager.isStreamingActive
    }

    private var statusLabel: String {

        switch manager.streamState {
        case .streaming:
            return "Streaming"
        case .connecting:
            return "Connecting"
        case .degraded:
            return "Degraded"
        case .reconnecting:
            return "Reconnecting"
        case .paused:
            return "Paused"
        case .failed:
            return "Error"
        case .stopped:

            break
        case .idle:
            break
        }

        switch manager.registrationState {
        case .unconfigured:
            return "Not Configured"
        case .configured:
            return "Configured"
        case .registrationRequired:
            return "Tap to Register"
        case .registering:
            return "Registering..."
        case .registered:
            return "Connected"
        case .failed:
            return "Error"
        }
    }

    private var statusSubtitle: String? {
        if case .failed(let msg) = manager.streamState {
            return msg
        }
        if case .failed(let msg) = manager.registrationState {
            return msg
        }
        if let error = manager.lastErrorMessage {
            return error
        }
        if isStreaming {
            return "\(manager.acceptedFrameCount) frames captured"
        }
        if case .registered = manager.registrationState {
            if let deviceType = manager.connectedDeviceType {
                return deviceType
            }
            return "Ready to stream"
        }
        if case .registrationRequired = manager.registrationState {
            return "Open Settings to register with Meta"
        }
        return nil
    }

    private var accentColor: Color {
        if case .failed = manager.streamState { return .red }
        if case .failed = manager.registrationState { return .red }
        if isStreaming { return .spatialCyan }
        if case .registered = manager.registrationState { return .confirmGreen }
        if case .registering = manager.registrationState { return .warningAmber }
        return .warningAmber
    }
}

private struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
