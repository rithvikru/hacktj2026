import SwiftUI

struct QueryResultView: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Result type + confidence indicator
            HStack(spacing: 8) {
                ConfidenceIndicator(level: result.resultType)
                    .frame(width: 20, height: 20)

                Text(resultTypeLabel)
                    .font(SpatialFont.caption)
                    .foregroundStyle(resultTypeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(resultTypeColor.opacity(0.15), in: Capsule())

                Spacer()

                Text("\(Int(result.confidence * 100))%")
                    .font(SpatialFont.dataMedium)
                    .foregroundStyle(.spatialCyan)
            }

            // Object label
            Text(result.label)
                .font(SpatialFont.title2)
                .foregroundStyle(.white)

            // Explanation
            Text(result.explanation)
                .font(SpatialFont.body)
                .foregroundStyle(.dimLabel)

            // Evidence sources
            if !result.evidence.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(result.evidence, id: \.self) { source in
                            Text(source)
                                .font(SpatialFont.caption)
                                .foregroundStyle(.spatialCyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.spatialCyan.opacity(0.15), in: Capsule())
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
        .glassBackground(cornerRadius: 24)
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
        case .confirmedHigh, .confirmedMedium: return .spatialCyan
        case .lastSeen:         return .warningAmber
        case .signalEstimated:  return .signalMagenta
        case .likelihoodRanked: return .inferenceViolet
        case .noResult:         return .dimLabel
        }
    }
}
