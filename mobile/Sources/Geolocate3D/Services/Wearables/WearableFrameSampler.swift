import Foundation

struct WearableFrameSampler {
    let targetFPS: Double
    private(set) var lastAcceptedAt: Date?

    init(targetFPS: Double = 1.0) {
        self.targetFPS = max(targetFPS, 0.2)
    }

    mutating func shouldSample(at timestamp: Date, reason: String) -> Bool {
        if reason == "transition" || reason == "detection_burst" {
            lastAcceptedAt = timestamp
            return true
        }

        guard let lastAcceptedAt else {
            self.lastAcceptedAt = timestamp
            return true
        }

        let minimumInterval = 1.0 / targetFPS
        if timestamp.timeIntervalSince(lastAcceptedAt) >= minimumInterval {
            self.lastAcceptedAt = timestamp
            return true
        }
        return false
    }
}
