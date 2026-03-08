import SwiftUI

struct StatusChip: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(SpatialFont.caption)
            .foregroundStyle(chipColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(chipColor.opacity(0.15), in: Capsule())
    }

    private var chipColor: Color {
        switch status.lowercased() {
        case "complete":   return .confirmGreen
        case "processing": return .spatialCyan
        case "pending":    return .mutedSlate
        case "failed":     return .signalMagenta
        default:           return .dimLabel
        }
    }
}
