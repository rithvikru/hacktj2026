import Foundation
import UIKit

struct FrameBundleManifest: Codable {
    let roomID: UUID
    let sessionID: UUID
    let createdAt: Date
    let frameCount: Int
    let device: DeviceMetadata
    let assetEncoding: AssetEncoding
    let captureProfile: CaptureProfile
    let keyframeSelection: KeyframeSelection
    let auxiliaryAssets: [FrameAuxiliaryAssets]
    let frames: [FrameRecord]

    @MainActor
    init(
        roomID: UUID,
        sessionID: UUID,
        frames: [FrameRecord],
        auxiliaryAssets: [FrameAuxiliaryAssets],
        captureProfile: CaptureProfile,
        keyframeSelection: KeyframeSelection
    ) {
        self.roomID = roomID
        self.sessionID = sessionID
        self.createdAt = Date()
        self.frameCount = frames.count
        self.device = DeviceMetadata.current()
        self.assetEncoding = AssetEncoding()
        self.captureProfile = captureProfile
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
        case captureProfile = "capture_profile"
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
    let rgb: String
    let depth: String
    let confidence: String
    let jpegQuality: Double

    init(
        rgb: String = "jpeg",
        depth: String = "png16_mm",
        confidence: String = "png8",
        jpegQuality: Double = 0.97
    ) {
        self.rgb = rgb
        self.depth = depth
        self.confidence = confidence
        self.jpegQuality = jpegQuality
    }

    enum CodingKeys: String, CodingKey {
        case rgb
        case depth
        case confidence
        case jpegQuality = "jpeg_quality"
    }
}

struct CaptureProfile: Codable {
    let profileID: String
    let intendedUse: String
    let targetOverlap: String
    let samplingIntervalSeconds: Double
    let minimumTranslationMeters: Float
    let minimumRotationRadians: Float

    static let denseTwin = CaptureProfile(
        profileID: "dense_room_twin_v1",
        intendedUse: "photoreal_dense_reconstruction",
        targetOverlap: "high",
        samplingIntervalSeconds: 0.20,
        minimumTranslationMeters: 0.04,
        minimumRotationRadians: 0.08
    )

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case intendedUse = "intended_use"
        case targetOverlap = "target_overlap"
        case samplingIntervalSeconds = "sampling_interval_seconds"
        case minimumTranslationMeters = "minimum_translation_meters"
        case minimumRotationRadians = "minimum_rotation_radians"
    }
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
