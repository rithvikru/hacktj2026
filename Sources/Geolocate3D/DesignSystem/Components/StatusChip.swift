import SwiftUI

struct StatusChip: View {
    let status: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(status.capitalized)
                .font(SpatialFont.caption)
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(chipColor.opacity(0.15), in: Capsule())
    }

    private var chipColor: Color {
        switch status.lowercased() {
        case "complete":   return .confirmGreen
        case "processing": return .spatialCyan
        case "pending":    return .warningAmber
        case "failed":     return .signalMagenta
        default:           return .dimLabel
        }
    }

    private var iconName: String {
        switch status.lowercased() {
        case "complete":   return "checkmark.circle.fill"
        case "processing": return "arrow.triangle.2.circlepath"
        case "pending":    return "clock.fill"
        case "failed":     return "exclamationmark.triangle.fill"
        default:           return "questionmark.circle"
        }
    }
}
