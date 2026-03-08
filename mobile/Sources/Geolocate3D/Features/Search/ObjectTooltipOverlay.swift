import SwiftUI

/// Screen-space positioned tooltip for detected objects in AR view.
struct ObjectTooltipOverlay: View {
    let observation: ScreenObservation

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                ConfidenceIndicator(level: observation.confidenceClass)
                    .frame(width: 10, height: 10)

                Text(observation.label)
                    .font(SpatialFont.headline)
                    .foregroundStyle(.white)
            }

            Text("\(Int(observation.confidence * 100))%")
                .font(SpatialFont.dataSmall)
                .foregroundStyle(.spatialCyan.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.elevatedSurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        }
    }
}
