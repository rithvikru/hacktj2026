import SwiftUI

/// Screen-space positioned tooltip for detected objects in AR view.
struct ObjectTooltipOverlay: View {
    let observation: ScreenObservation

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ConfidenceIndicator(level: observation.confidenceClass)
                    .frame(width: 12, height: 12)

                Text(observation.label)
                    .font(SpatialFont.headline)
                    .foregroundStyle(.white)
            }

            Text("\(Int(observation.confidence * 100))%")
                .font(SpatialFont.dataSmall)
                .foregroundStyle(.spatialCyan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}
