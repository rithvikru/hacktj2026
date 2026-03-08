import SwiftUI

struct AnnotationPin: View {
    let observation: ObjectObservation
    var isSelected: Bool = false
    var showLabel: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            if showLabel {
                Text(observation.label)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(Int(observation.confidence * 100))%")
                    .font(SpatialFont.dataSmall)
                    .foregroundStyle(confidenceColor.opacity(0.9))
            } else {
                // Compact dot-only mode
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, showLabel ? 10 : 4)
        .padding(.vertical, showLabel ? 6 : 4)
        .background(Color.elevatedSurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: showLabel ? 10 : 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: showLabel ? 10 : 6, style: .continuous)
                .stroke(
                    isSelected ? Color.spatialCyan : confidenceColor.opacity(0.3),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
    }

    private var confidenceColor: Color {
        switch observation.confidenceClass {
        case .confirmedHigh: return .confirmGreen
        case .confirmedMedium: return .spatialCyan
        case .lastSeen: return .warningAmber
        case .signalEstimated: return .signalMagenta
        case .likelihoodRanked: return .inferenceViolet
        case .noResult: return .dimLabel
        }
    }
}
