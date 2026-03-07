// DesignSystem/Components/ScanStatusPill.swift
import SwiftUI

enum ScanState: Equatable {
    case initializing
    case scanning
    case processing
    case ready
    case saving
    case error(String)
}

struct ScanStatusPill: View {
    let state: ScanState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(label)
                .font(SpatialFont.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private var dotColor: Color {
        switch state {
        case .initializing: return .warningAmber
        case .scanning:     return .spatialCyan
        case .processing:   return .inferenceViolet
        case .ready:        return .confirmGreen
        case .saving:       return .spatialCyan
        case .error:        return .signalMagenta
        }
    }

    private var label: String {
        switch state {
        case .initializing: return "Initializing"
        case .scanning:     return "Scanning"
        case .processing:   return "Processing"
        case .ready:        return "Ready"
        case .saving:       return "Saving"
        case .error(let msg): return msg
        }
    }
}
