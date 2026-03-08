import Observation
import Foundation

@Observable
final class ObjectHypothesis: Identifiable {
    var id: UUID
    var queryLabel: String
    var hypothesisTypeRaw: String
    var rank: Int
    var confidence: Double
    var transformData: Data?
    var reasonCodes: [String]
    var generatedAt: Date

    var room: RoomRecord?

    var hypothesisType: HypothesisType {
        HypothesisType(rawValue: hypothesisTypeRaw) ?? .inferred
    }

    var confidenceClass: DetectionConfidenceClass {
        switch hypothesisType {
        case .cooperative: return .signalEstimated
        case .tagged: return .signalEstimated
        case .inferred: return .likelihoodRanked
        }
    }

    init(queryLabel: String, type: HypothesisType, rank: Int,
         confidence: Double, reasons: [String]) {
        self.id = UUID()
        self.queryLabel = queryLabel
        self.hypothesisTypeRaw = type.rawValue
        self.rank = rank
        self.confidence = confidence
        self.reasonCodes = reasons
        self.generatedAt = Date()
    }
}
