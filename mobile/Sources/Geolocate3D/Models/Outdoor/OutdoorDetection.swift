import Foundation
import CoreLocation

struct OutdoorDetection: Codable, Identifiable, Hashable {
    let id: UUID
    let label: String
    let confidence: Double
    let latitude: Double
    let longitude: Double
    let frameID: UUID
    let timestamp: Date
    let boundingBox: CodableRect?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        label: String,
        confidence: Double,
        latitude: Double,
        longitude: Double,
        frameID: UUID,
        timestamp: Date = Date(),
        boundingBox: CodableRect? = nil
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.latitude = latitude
        self.longitude = longitude
        self.frameID = frameID
        self.timestamp = timestamp
        self.boundingBox = boundingBox
    }
}

struct CodableRect: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
