import SwiftUI

struct ObjectTooltip: View {
    let label: String
    let confidence: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(SpatialFont.headline)
                .foregroundStyle(.white)
            Text("\(Int(confidence * 100))%")
                .font(SpatialFont.dataSmall)
                .foregroundStyle(.spatialCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}
