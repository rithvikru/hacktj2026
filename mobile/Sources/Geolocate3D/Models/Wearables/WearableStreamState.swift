import Foundation
import UIKit

enum WearableRegistrationState: Equatable {
    case unconfigured
    case configured
    case registrationRequired
    case registering
    case registered
    case failed(String)
}

enum WearableStreamState: Equatable {
    case idle
    case connecting
    case streaming
    case degraded
    case reconnecting
    case paused
    case stopped
    case failed(String)
}

struct WearableObservedObjectPayload: Codable, Hashable {
    let label: String
    let confidence: Double
}

struct WearableCapturedFrame {
    let id: UUID
    let timestamp: Date
    let image: UIImage
    let placeHint: String?
    let observedObjects: [WearableObservedObjectPayload]
    let sampleReason: String
    let width: Int
    let height: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        image: UIImage,
        placeHint: String? = nil,
        observedObjects: [WearableObservedObjectPayload] = [],
        sampleReason: String = "interval",
        width: Int,
        height: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.image = image
        self.placeHint = placeHint
        self.observedObjects = observedObjects
        self.sampleReason = sampleReason
        self.width = width
        self.height = height
    }
}

struct WearableFrameUpload: Encodable {
    let frameID: String
    let timestamp: String
    let sampleReason: String
    let placeHint: String?
    let observedObjects: [WearableObservedObjectPayload]
    let imageJPEGBase64: String?
    let imageWidth: Int
    let imageHeight: Int
    let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case frameID = "frame_id"
        case timestamp
        case sampleReason = "sample_reason"
        case placeHint = "place_hint"
        case observedObjects = "observed_objects"
        case imageJPEGBase64 = "image_jpeg_base64"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case metadata
    }
}
