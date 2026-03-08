import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class OutdoorMapViewModel {
    var isCapturing = false
    var searchQuery = ""
    var searchResults: [OutdoorDetection] = []
    var captureError: String?

    private var outdoorSessionID: UUID?

    func startCapture(
        wearableManager: WearableStreamSessionManager,
        store: OutdoorSessionStore,
        locationService: LocationService
    ) {
        guard !isCapturing else { return }
        captureError = nil

        let session = store.startSession()
        outdoorSessionID = session.id
        locationService.startUpdating()

        wearableManager.onFrameAccepted = { [weak self] frame, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCapturing else { return }
                guard let location = locationService.currentLocation else { return }
                guard let sessionID = self.outdoorSessionID else { return }

                let outdoorFrame = OutdoorFrame(
                    sessionID: sessionID,
                    location: location,
                    imagePath: ""
                )
                store.addFrame(outdoorFrame)
            }
        }

        isCapturing = true
        Task {
            await wearableManager.startStreaming(
                homeID: "outdoor-\(session.id.uuidString)",
                placeHint: gpsPlaceHint(locationService: locationService)
            )

            if case .failed(let msg) = wearableManager.streamState {
                captureError = msg
                isCapturing = false
                store.endSession()
                wearableManager.onFrameAccepted = nil
            }
        }
    }

    func stopCapture(
        wearableManager: WearableStreamSessionManager,
        store: OutdoorSessionStore
    ) {
        isCapturing = false
        wearableManager.onFrameAccepted = nil
        Task {
            await wearableManager.stopStreaming()
        }
        store.endSession()
        outdoorSessionID = nil
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

    private func gpsPlaceHint(locationService: LocationService) -> String? {
        guard let loc = locationService.currentLocation else { return nil }
        return String(format: "%.5f,%.5f", loc.coordinate.latitude, loc.coordinate.longitude)
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
