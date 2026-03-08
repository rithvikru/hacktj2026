import Foundation
import Observation

@Observable
@MainActor
final class OutdoorSessionStore {
    private(set) var currentSession: OutdoorSession?
    private(set) var frames: [OutdoorFrame] = []
    private(set) var detections: [OutdoorDetection] = []

    private let frameCap = 500

    func startSession() -> OutdoorSession {
        let session = OutdoorSession()
        currentSession = session
        frames.removeAll()
        detections.removeAll()
        return session
    }

    func endSession() {
        currentSession?.endedAt = Date()
    }

    func addFrame(_ frame: OutdoorFrame) {
        frames.append(frame)
        currentSession?.frameCount = frames.count

        if frames.count > frameCap {
            let evicted = frames.removeFirst()

            detections.removeAll { $0.frameID == evicted.id }
        }
    }

    func addDetections(_ newDetections: [OutdoorDetection]) {
        detections.append(contentsOf: newDetections)
    }

    func frame(for id: UUID) -> OutdoorFrame? {
        frames.first { $0.id == id }
    }

    func detections(near coordinate: (Double, Double), radius: Double = 10) -> [OutdoorDetection] {
        detections.filter { detection in
            let latDiff = detection.latitude - coordinate.0
            let lonDiff = detection.longitude - coordinate.1

            let distMeters = sqrt(latDiff * latDiff + lonDiff * lonDiff) * 111_000
            return distMeters <= radius
        }
    }
}
