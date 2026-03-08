import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let query: String
    let resultType: DetectionConfidenceClass
    let label: String
    let confidence: Double
    let explanation: String
    let evidence: [String]
    let timestamp: Date
    let confidenceState: SearchConfidenceState
    let roomName: String?
    let placeID: String?
    let recencySeconds: Double?
    let memoryFreshness: Double?
    let routeHint: String?
}
