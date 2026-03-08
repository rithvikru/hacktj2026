import Foundation

enum DetectionConfidenceClass: String, Codable {
    case confirmedHigh, confirmedMedium, lastSeen
    case signalEstimated, likelihoodRanked, staleMemory, noResult
}
