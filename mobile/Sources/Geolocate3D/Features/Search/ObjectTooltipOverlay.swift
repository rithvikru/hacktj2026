import SwiftUI

struct ObjectTooltipOverlay: View {
    let observation: ScreenObservation

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ConfidenceIndicator(level: observation.confidenceClass)
                    .frame(width: 16, height: 16)

                Text(observation.label)
                    .font(SpatialFont.title2)
                    .foregroundStyle(.white)
            }

            Text("\(Int(observation.confidence * 100))%")
                .font(SpatialFont.dataMedium)
                .foregroundStyle(.spatialCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.spaceBlack.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.spatialCyan, lineWidth: 2)
        }
        .shadow(color: .spatialCyan.opacity(0.5), radius: 12)
    }
}
