import SwiftData
import Foundation
import UIKit

@Model
final class RoomRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var previewImagePath: String?
    var capturedRoomJSONPath: String?
    var roomUSDZPath: String?
    @Attribute(.externalStorage) var worldMapData: Data?
    var frameBundlePath: String?
    var denseAssetPath: String?
    var sceneGraphVersion: Int
    var reconstructionStatusRaw: String

    @Relationship(deleteRule: .cascade, inverse: \ObjectObservation.room)
    var observations: [ObjectObservation] = []

    @Relationship(deleteRule: .cascade, inverse: \SceneNode.room)
    var sceneNodes: [SceneNode] = []

    @Relationship(deleteRule: .cascade, inverse: \ObjectHypothesis.room)
    var hypotheses: [ObjectHypothesis] = []

    var reconstructionStatus: ReconstructionStatus {
        get { ReconstructionStatus(rawValue: reconstructionStatusRaw) ?? .pending }
        set { reconstructionStatusRaw = newValue.rawValue }
    }

    @Transient var observationCount: Int { observations.count }

    @Transient var previewImage: UIImage? {
        guard let path = previewImagePath else { return nil }
        return UIImage(contentsOfFile: path)
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sceneGraphVersion = 0
        self.reconstructionStatusRaw = ReconstructionStatus.pending.rawValue
    }
}
