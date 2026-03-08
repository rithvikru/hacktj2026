import SwiftUI

struct QueryResultView: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

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

            Text(result.label)
                .font(SpatialFont.title2)
                .foregroundStyle(.white)

            Text(result.explanation)
                .font(SpatialFont.body)
                .foregroundStyle(.dimLabel)

            if let roomName = result.roomName {
                Label(roomName, systemImage: "house")
                    .font(SpatialFont.caption)
                    .foregroundStyle(.white)
            }

            if let routeHint = result.routeHint {
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(.spatialCyan)
                    Text(routeHint)
                        .font(SpatialFont.caption)
                        .foregroundStyle(.spatialCyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.spatialCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                Text(result.confidenceState.displayLabel)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(confidenceStateColor.opacity(0.18), in: Capsule())

                if let freshness = result.memoryFreshness {
                    Text("Freshness \(Int(freshness * 100))%")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }

                if let recency = result.recencySeconds {
                    Text(recencyLabel(for: recency))
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }
            }

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
        case .staleMemory:      return "Stale"
        case .noResult:         return "Not found"
        }
    }

    private var resultTypeColor: Color {
        switch result.resultType {
        case .confirmedHigh, .confirmedMedium: return .spatialCyan
        case .lastSeen:         return .warningAmber
        case .signalEstimated:  return .signalMagenta
        case .likelihoodRanked: return .inferenceViolet
        case .staleMemory:      return .warningAmber
        case .noResult:         return .dimLabel
        }
    }

    private var confidenceStateColor: Color {
        switch result.confidenceState {
        case .liveSeen:
            return .spatialCyan
        case .lastSeen:
            return .warningAmber
        case .likelyHidden:
            return .inferenceViolet
        case .staleMemory:
            return .warningAmber
        case .notFound:
            return .dimLabel
        }
    }

    private func recencyLabel(for recency: Double) -> String {
        if recency < 60 {
            return "seen just now"
        }
        if recency < 3600 {
            return "seen \(Int(recency / 60))m ago"
        }
        if recency < 86400 {
            return "seen \(Int(recency / 3600))h ago"
        }
        return "seen \(Int(recency / 86400))d ago"
    }
}
