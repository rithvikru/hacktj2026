import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class OutdoorMapViewModel {
    var isCapturing = false
    var searchQuery = ""
    var searchResults: [OutdoorDetection] = []

    private var captureTimer: Timer?

    func startCapture(store: OutdoorSessionStore, locationService: LocationService) {
        guard !isCapturing else { return }
        isCapturing = true
        _ = store.startSession()
        locationService.startUpdating()

        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCapturing else { return }
                guard let location = locationService.currentLocation else { return }
                guard let session = store.currentSession else { return }

                let frame = OutdoorFrame(
                    sessionID: session.id,
                    location: location,
                    imagePath: ""
                )
                store.addFrame(frame)
            }
        }
    }

    func stopCapture(store: OutdoorSessionStore) {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        store.endSession()
    }

    func clusteredDetections(from detections: [OutdoorDetection]) -> [OutdoorDetection] {
        guard !detections.isEmpty else { return [] }

        var clusters: [OutdoorDetection] = []
        var used = Set<UUID>()

        for detection in detections {
            guard !used.contains(detection.id) else { continue }
            used.insert(detection.id)

            var best = detection
            for other in detections where !used.contains(other.id) {
                let distance = Self.distance(
                    lat1: detection.latitude, lon1: detection.longitude,
                    lat2: other.latitude, lon2: other.longitude
                )
                if distance < 5 && other.label == detection.label {
                    used.insert(other.id)
                    if other.confidence > best.confidence {
                        best = other
                    }
                }
            }
            clusters.append(best)
        }

        return clusters
    }

    func performSearch(query: String, store: OutdoorSessionStore) async {

        let lowered = query.lowercased()
        searchResults = store.detections.filter {
            $0.label.lowercased().contains(lowered)
        }

    }

    private static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return 6_371_000 * c
    }
}
