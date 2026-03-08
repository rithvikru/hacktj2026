import Foundation

struct LiveRouteTarget: Hashable {
    let objectID: String?
    let label: String
    let worldTransform16: [Float]?

    var routeIDComponent: String {
        if let objectID, !objectID.isEmpty {
            return objectID
        }
        return label.replacingOccurrences(of: " ", with: "-").lowercased()
    }
}

// MARK: - Hierarchical Push Destinations (NavigationStack)

enum NavigationRoute: Hashable {
    case roomTwin(roomID: UUID)
    case hiddenSearch(roomID: UUID)
    case objectDetail(observationID: UUID)
}

// MARK: - Immersive Full-Screen AR Destinations

enum FullScreenRoute: Identifiable {
    case scanRoom
    case liveSearch(roomID: UUID?, target: LiveRouteTarget? = nil)
    case companionTarget

    var id: String {
        switch self {
        case .scanRoom: return "scanRoom"
        case .liveSearch(let id, let target):
            return "liveSearch-\(id?.uuidString ?? "new")-\(target?.routeIDComponent ?? "default")"
        case .companionTarget: return "companionTarget"
        }
    }
}

// MARK: - Contextual Sheet Destinations

enum SheetRoute: Identifiable {
    case queryConsole(roomID: UUID?)
    case scanResults(roomID: UUID)
    case objectDetail(observationID: UUID)

    var id: String {
        switch self {
        case .queryConsole(let id): return "query-\(id?.uuidString ?? "global")"
        case .scanResults(let id): return "scanResults-\(id.uuidString)"
        case .objectDetail(let id): return "objectDetail-\(id.uuidString)"
        }
    }
}
