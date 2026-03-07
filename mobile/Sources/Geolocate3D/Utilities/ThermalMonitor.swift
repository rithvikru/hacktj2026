import Foundation

/// Monitors device thermal state and provides adaptive performance levels.
/// Extends beyond just detection FPS — gates animations, writes, and reconstruction too.
@Observable
@MainActor
final class ThermalMonitor {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var performanceLevel: PerformanceLevel = .full

    enum PerformanceLevel {
        case full      // All features at max quality
        case reduced   // Lower FPS, disable glow animations, reduce write frequency
        case minimal   // Pause detection, simplify rendering, disable reconstruction

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
