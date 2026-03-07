import SwiftUI

struct HypothesisCard: View {
    let hypothesis: ObjectHypothesis
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConfidenceIndicator(level: hypothesis.confidenceClass)
                    .frame(width: 32, height: 32)
                Spacer()
                Text("#\(hypothesis.rank)")
                    .font(SpatialFont.dataSmall)
                    .foregroundStyle(.dimLabel)
            }

            Text(hypothesis.queryLabel)
                .font(SpatialFont.headline)
                .foregroundStyle(.white)

            Text(hypothesis.reasonCodes.first ?? "")
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
                .lineLimit(2)

            HStack {
                Text("\(Int(hypothesis.confidence * 100))%")
                    .font(SpatialFont.dataMedium)
                    .foregroundStyle(.inferenceViolet)
                Spacer()
                Text(hypothesis.hypothesisType.label)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isSelected ? Color.inferenceViolet.opacity(0.8) : .white.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .if(isSelected) { view in
            view.spatialGlow(color: .inferenceViolet, cornerRadius: 24, intensity: 0.6)
        }
    }
}
