import Foundation

enum NavigationRoute: Hashable {
    case roomTwin(roomID: UUID)
    case hiddenSearch(roomID: UUID)
    case objectDetail(observationID: UUID)
}

enum FullScreenRoute: Identifiable {
    case scanRoom
    case liveSearch(roomID: UUID?)
    case companionTarget
    case outdoorCapture

    var id: String {
        switch self {
        case .scanRoom: return "scanRoom"
        case .liveSearch(let id): return "liveSearch-\(id?.uuidString ?? "new")"
        case .companionTarget: return "companionTarget"
        case .outdoorCapture: return "outdoorCapture"
        }
    }
}

enum SheetRoute: Identifiable {
    case queryConsole(roomID: UUID?)
    case scanResults(roomID: UUID)
    case objectDetail(observationID: UUID)
    case framePreview(detectionID: UUID)

    var id: String {
        switch self {
        case .queryConsole(let id): return "query-\(id?.uuidString ?? "global")"
        case .scanResults(let id): return "scanResults-\(id.uuidString)"
        case .objectDetail(let id): return "objectDetail-\(id.uuidString)"
        case .framePreview(let id): return "framePreview-\(id.uuidString)"
        }
    }
}
