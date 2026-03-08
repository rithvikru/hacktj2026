import SwiftUI

struct HypothesisCard: View {
    let hypothesis: ObjectHypothesis
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConfidenceIndicator(level: hypothesis.confidenceClass)
                    .frame(width: 28, height: 28)
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
        .padding(14)
        .frame(width: 200)
        .background(Color.elevatedSurface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? Color.inferenceViolet.opacity(0.5) : Color.white.opacity(0.05),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .shadow(color: isSelected ? .inferenceViolet.opacity(0.1) : .black.opacity(0.15), radius: isSelected ? 12 : 6, y: 4)
    }
}
