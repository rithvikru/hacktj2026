import Foundation
import CoreLocation

struct OutdoorFrame: Codable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let imagePath: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isLocated: Bool {
        horizontalAccuracy < 100
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date = Date(),
        location: CLLocation,
        imagePath: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.imagePath = imagePath
    }
}
