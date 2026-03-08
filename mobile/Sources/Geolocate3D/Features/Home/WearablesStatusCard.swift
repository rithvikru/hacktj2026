import SwiftUI
import UIKit

struct UnifiedDeviceCard: View {
    @Environment(WearableStreamSessionManager.self) private var manager

    var body: some View {
        HStack(spacing: 16) {

            glassesImage
                .frame(width: 100, height: 70)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(deviceName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                if let detail = statusDetail {
                    Text(detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.zinc900, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var glassesImage: some View {
        if let img = UIImage(named: "rayban-meta", in: .module, compatibleWith: nil) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {

            Text("Ray-Ban Meta")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.zinc900)
        }
    }

    private var deviceName: String {
        manager.connectedDeviceName ?? "Ray-Ban Meta"
    }

    private var statusColor: Color {
        if manager.isStreamingActive { return .spatialCyan }
        switch manager.registrationState {
        case .registered: return .confirmGreen
        case .registering: return .mutedSlate
        case .failed: return .red.opacity(0.8)
        default: return .mutedSlate
        }
    }

    private var statusLabel: String {

        switch manager.streamState {
        case .streaming: return "Streaming"
        case .connecting: return "Connecting"
        case .degraded: return "Degraded"
        case .reconnecting: return "Reconnecting"
        case .paused: return "Paused"
        case .failed: return "Error"
        case .stopped, .idle: break
        }

        switch manager.registrationState {
        case .unconfigured: return "Not configured"
        case .configured: return "Configured"
        case .registrationRequired: return "Not registered"
        case .registering: return "Registering..."
        case .registered: return "Connected"
        case .failed: return "Error"
        }
    }

    private var statusDetail: String? {
        if case .failed(let msg) = manager.streamState { return msg }
        if case .failed(let msg) = manager.registrationState { return msg }
        if let error = manager.lastErrorMessage { return error }
        if manager.isStreamingActive {
            return "\(manager.acceptedFrameCount) frames captured"
        }
        if case .registered = manager.registrationState {
            return manager.connectedDeviceType ?? "Ready to stream"
        }
        return nil
    }
}
