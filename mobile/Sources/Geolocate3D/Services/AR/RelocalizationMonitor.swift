import ARKit

@Observable
@MainActor
final class RelocalizationMonitor {
    enum State: Equatable {
        case idle
        case relocalizing
        case relocalized
        case failed
    }

    var state: State = .idle
    var elapsedTime: TimeInterval = 0

    private var timeoutTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private static let timeoutSeconds: TimeInterval = 30

    var statusMessage: String {
        switch state {
        case .idle:         return ""
        case .relocalizing: return "Relocalizing... \(Int(elapsedTime))s"
        case .relocalized:  return "Relocalized"
        case .failed:       return "Relocalization failed — try moving to a previously scanned area"
        }
    }

    func bind(to sessionManager: SpatialSessionManager) {
        if sessionManager.worldMappingStatus == .mapped {
            state = .relocalized
            return
        }

        guard state == .idle else { return }
        state = .relocalizing
        elapsedTime = 0
        startTimer()
        startTimeout()
    }

    func update(trackingState: ARCamera.TrackingState,
                mappingStatus: ARFrame.WorldMappingStatus) {
        guard state == .relocalizing else { return }

        if trackingState == .normal && mappingStatus == .mapped {
            state = .relocalized
            cancelAll()
        }
    }

    func reset() {
        cancelAll()
        state = .idle
        elapsedTime = 0
    }

    private func startTimeout() {
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
            if !Task.isCancelled && state == .relocalizing {
                state = .failed
                cancelAll()
            }
        }
    }

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled && state == .relocalizing {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled {
                    elapsedTime += 1
                }
            }
        }
    }

    private func cancelAll() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timerTask?.cancel()
        timerTask = nil
    }
}
