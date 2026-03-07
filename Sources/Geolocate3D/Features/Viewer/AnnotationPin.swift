import SwiftUI

struct AnnotationPin: View {
    let observation: ObjectObservation

    var body: some View {
        VStack(spacing: 4) {
            Text(observation.label)
                .font(SpatialFont.caption)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(Int(observation.confidence * 100))%")
                .font(SpatialFont.dataSmall)
                .foregroundStyle(confidenceColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(confidenceColor.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var confidenceColor: Color {
        switch observation.confidenceClass {
        case .confirmedHigh: return .spatialCyan
        case .confirmedMedium: return .spatialCyan.opacity(0.7)
        case .lastSeen: return .warningAmber
        case .signalEstimated: return .signalMagenta
        case .likelihoodRanked: return .inferenceViolet
        case .noResult: return .dimLabel
        }
    }
}
