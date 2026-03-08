// DesignSystem/Components/TrackingStatusBadge.swift
import SwiftUI

/// Placeholder tracking quality state.
/// Replace with ARCamera.TrackingState mapping in the AR layer.
enum TrackingQuality: String {
    case notAvailable
    case limited
    case normal
}

struct TrackingStatusBadge: View {
    let quality: TrackingQuality

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(label)
                .font(SpatialFont.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.elevatedSurface.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
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
