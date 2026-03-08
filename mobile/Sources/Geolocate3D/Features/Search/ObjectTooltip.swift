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
                .foregroundStyle(.spatialCyan.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.elevatedSurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        }
    }
}
