import Foundation
import UIKit

struct FrameBundleManifest: Codable {
    let roomID: UUID
    let sessionID: UUID
    let createdAt: Date
    let frameCount: Int
    let device: DeviceMetadata
    let assetEncoding: AssetEncoding
    let keyframeSelection: KeyframeSelection
    let auxiliaryAssets: [FrameAuxiliaryAssets]
    let frames: [FrameRecord]

    @MainActor init(
        roomID: UUID,
        sessionID: UUID,
        frames: [FrameRecord],
        auxiliaryAssets: [FrameAuxiliaryAssets],
        keyframeSelection: KeyframeSelection
    ) {
        self.roomID = roomID
        self.sessionID = sessionID
        self.createdAt = Date()
        self.frameCount = frames.count
        self.device = DeviceMetadata.current()
        self.assetEncoding = AssetEncoding()
        self.keyframeSelection = keyframeSelection
        self.auxiliaryAssets = auxiliaryAssets
        self.frames = frames
    }

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case sessionID = "session_id"
        case createdAt = "created_at"
        case frameCount = "frame_count"
        case device
        case assetEncoding = "asset_encoding"
        case keyframeSelection = "keyframe_selection"
        case auxiliaryAssets = "auxiliary_assets"
        case frames
    }
}

struct FrameAuxiliaryAssets: Codable {
    let frameID: UUID
    let confidenceMapPath: String?

    enum CodingKeys: String, CodingKey {
        case frameID = "frame_id"
        case confidenceMapPath = "confidence_map_path"
    }
}

struct KeyframeSelection: Codable {
    let minimumIntervalSeconds: Double
    let maximumIntervalSeconds: Double
    let minimumTranslationMeters: Float
    let minimumRotationRadians: Float

    enum CodingKeys: String, CodingKey {
        case minimumIntervalSeconds = "minimum_interval_seconds"
        case maximumIntervalSeconds = "maximum_interval_seconds"
        case minimumTranslationMeters = "minimum_translation_meters"
        case minimumRotationRadians = "minimum_rotation_radians"
    }
}

struct AssetEncoding: Codable {
    let rgb: String = "jpeg"
    let depth: String = "png16_mm"
    let confidence: String = "png8"
}

struct DeviceMetadata: Codable {
    let model: String
    let systemName: String
    let systemVersion: String

    @MainActor static func current() -> DeviceMetadata {
        let device = UIDevice.current
        return DeviceMetadata(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case systemName = "system_name"
        case systemVersion = "system_version"
    }
}
