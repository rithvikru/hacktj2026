import Foundation

@Observable
@MainActor
final class ThermalMonitor {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var performanceLevel: PerformanceLevel = .full

    enum PerformanceLevel {
        case full
        case reduced
        case minimal

        var detectionFPS: Double {
            switch self {
            case .full: return 10.0
            case .reduced: return 4.0
            case .minimal: return 0.0
            }
        }

        var enableGlowAnimations: Bool {
            self == .full
        }

        var swiftDataWriteInterval: TimeInterval {
            switch self {
            case .full: return 5.0
            case .reduced: return 15.0
            case .minimal: return 30.0
            }
        }
    }

    init() {
        updateThermalState()
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
            }
        }
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal, .fair:
            performanceLevel = .full
        case .serious:
            performanceLevel = .reduced
        case .critical:
            performanceLevel = .minimal
        @unknown default:
            performanceLevel = .reduced
        }
    }
}
