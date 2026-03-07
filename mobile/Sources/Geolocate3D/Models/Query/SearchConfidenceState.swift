import Foundation

enum SearchConfidenceState: String, Codable {
    case liveSeen = "live_seen"
    case lastSeen = "last_seen"
    case likelyHidden = "likely_hidden"
    case staleMemory = "stale_memory"
    case notFound = "not_found"

    var displayLabel: String {
        switch self {
        case .liveSeen:
            return "Live"
        case .lastSeen:
            return "Remembered"
        case .likelyHidden:
            return "Inferred"
        case .staleMemory:
            return "Stale"
        case .notFound:
            return "Not Found"
        }
    }
}
