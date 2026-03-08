import Observation
import Foundation
import UIKit

@Observable
final class RoomRecord: Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var previewImagePath: String?
    var capturedRoomJSONPath: String?
    var roomUSDZPath: String?
    var worldMapData: Data?
    var frameBundlePath: String?
    var denseAssetPath: String?
    var sceneGraphVersion: Int
    var reconstructionStatusRaw: String

    var observations: [ObjectObservation] = []
    var sceneNodes: [SceneNode] = []
    var hypotheses: [ObjectHypothesis] = []

    var reconstructionStatus: ReconstructionStatus {
        get { ReconstructionStatus(rawValue: reconstructionStatusRaw) ?? .pending }
        set { reconstructionStatusRaw = newValue.rawValue }
    }

    var observationCount: Int { observations.count }

    var previewImage: UIImage? {
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
