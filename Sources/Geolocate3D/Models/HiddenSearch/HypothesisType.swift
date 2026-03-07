import Foundation

enum HypothesisType: String, Codable {
    case cooperative, tagged, inferred

    var label: String {
        switch self {
        case .cooperative: return "Cooperative"
        case .tagged: return "Tagged"
        case .inferred: return "Likely here"
        }
    }
}
