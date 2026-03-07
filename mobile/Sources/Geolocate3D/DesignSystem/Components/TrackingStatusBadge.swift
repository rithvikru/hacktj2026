import SwiftUI

enum TrackingQuality: String {
    case notAvailable
    case limited
    case normal
}

struct TrackingStatusBadge: View {
    let quality: TrackingQuality

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(label)
                .font(SpatialFont.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private var dotColor: Color {
        switch quality {
        case .notAvailable: return .signalMagenta
        case .limited:      return .warningAmber
        case .normal:       return .confirmGreen
        }
    }

    private var label: String {
        switch quality {
        case .notAvailable: return "No Tracking"
        case .limited:      return "Limited"
        case .normal:       return "Tracking"
        }
    }
}
