import Observation
import Foundation

@Observable
final class SceneNode: Identifiable {
    var id: UUID
    var roomID: UUID
    var nodeTypeRaw: String
    var label: String
    var worldTransform16: Data
    var extentXYZ: [Float]
    var parentID: UUID?
    var attributesJSON: String

    var room: RoomRecord?

    var nodeType: SceneNodeType {
        get { SceneNodeType(rawValue: nodeTypeRaw) ?? .room }
        set { nodeTypeRaw = newValue.rawValue }
    }

    init(roomID: UUID, nodeType: SceneNodeType, label: String,
         worldTransform: Data, extentXYZ: [Float] = [0, 0, 0],
         parentID: UUID? = nil, attributesJSON: String = "{}") {
        self.id = UUID()
        self.roomID = roomID
        self.nodeTypeRaw = nodeType.rawValue
        self.label = label
        self.worldTransform16 = worldTransform
        self.extentXYZ = extentXYZ
        self.parentID = parentID
        self.attributesJSON = attributesJSON
    }
}
