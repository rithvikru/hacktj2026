import SwiftUI

struct QueryResultView: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Result type + confidence
            HStack(spacing: 8) {
                ConfidenceIndicator(level: result.resultType)
                    .frame(width: 18, height: 18)

                Text(resultTypeLabel)
                    .font(SpatialFont.caption)
                    .foregroundStyle(resultTypeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(resultTypeColor.opacity(0.1), in: Capsule())

                Spacer()

                Text("\(Int(result.confidence * 100))%")
                    .font(SpatialFont.dataMedium)
                    .foregroundStyle(.white)
            }

            // Object label
            Text(result.label)
                .font(SpatialFont.title2)
                .foregroundStyle(.white)

            // Explanation
            Text(result.explanation)
                .font(SpatialFont.subheadline)
                .foregroundStyle(.dimLabel)
                .lineSpacing(2)

            // Evidence sources
            if !result.evidence.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(result.evidence, id: \.self) { source in
                            Text(source)
                                .font(SpatialFont.caption)
                                .foregroundStyle(.spatialCyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.spatialCyan.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }

            // Timestamp
            Text(result.timestamp.formatted(date: .omitted, time: .shortened))
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
        }
        .padding(16)
        .glassBackground(cornerRadius: 16)
    }

    private var resultTypeLabel: String {
        switch result.resultType {
        case .confirmedHigh, .confirmedMedium: return "Detected"
        case .lastSeen:         return "Last seen"
        case .signalEstimated:  return "Signal"
        case .likelihoodRanked: return "Likely here"
        case .noResult:         return "Not found"
        }
    }

    private var resultTypeColor: Color {
        switch result.resultType {
        case .confirmedHigh, .confirmedMedium: return .confirmGreen
        case .lastSeen:         return .warningAmber
        case .signalEstimated:  return .signalMagenta
        case .likelihoodRanked: return .inferenceViolet
        case .noResult:         return .dimLabel
        }
    }
}
