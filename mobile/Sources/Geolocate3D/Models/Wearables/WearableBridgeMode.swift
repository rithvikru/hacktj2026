import Foundation

enum WearableBridgeMode: String, CaseIterable, Identifiable {
    case meta
    case simulated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meta:
            return "Meta Glasses"
        case .simulated:
            return "Simulated"
        }
    }

    static func fromStoredValue(_ value: String?) -> WearableBridgeMode {
        guard let value, let mode = WearableBridgeMode(rawValue: value) else {
            return .meta
        }
        return mode
    }
}
