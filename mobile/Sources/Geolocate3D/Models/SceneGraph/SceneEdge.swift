import Observation
import Foundation

@Observable
final class SceneEdge: Identifiable {
    var id: UUID
    var roomID: UUID
    var sourceNodeID: UUID
    var targetNodeID: UUID
    var edgeTypeRaw: String
    var weight: Double?

    var edgeType: SceneEdgeType {
        get { SceneEdgeType(rawValue: edgeTypeRaw) ?? .near }
        set { edgeTypeRaw = newValue.rawValue }
    }

    init(roomID: UUID, sourceNodeID: UUID, targetNodeID: UUID,
         edgeType: SceneEdgeType, weight: Double? = nil) {
        self.id = UUID()
        self.roomID = roomID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.edgeTypeRaw = edgeType.rawValue
        self.weight = weight
    }
}
