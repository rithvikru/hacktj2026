// DesignSystem/Components/ConfidenceIndicator.swift
import SwiftUI

// DetectionConfidenceClass is defined in Models/Query/SearchClass.swift

struct ConfidenceIndicator: View {
    let level: DetectionConfidenceClass
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch level {
            case .confirmedHigh:
                Circle()
                    .fill(Color.confirmGreen.opacity(0.2))
                Circle()
                    .stroke(Color.confirmGreen, lineWidth: 2)
                Circle()
                    .fill(Color.confirmGreen)
                    .scaleEffect(0.35)

            case .confirmedMedium:
                Circle()
                    .fill(Color.spatialCyan.opacity(0.15))
                Circle()
                    .stroke(Color.spatialCyan.opacity(0.8), lineWidth: 1.5)

            case .lastSeen:
                Circle()
                    .stroke(Color.warningAmber.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.5 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }

            case .signalEstimated:
                Circle()
                    .fill(Color.signalMagenta.opacity(0.1))
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.signalMagenta.opacity(0.7), lineWidth: 1.5)
                    .rotationEffect(.degrees(pulse ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }

            case .likelihoodRanked:
                Circle()
                    .fill(Color.inferenceViolet.opacity(0.15))
                Circle()
                    .stroke(Color.inferenceViolet.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(pulse ? 1.04 : 0.96)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }

            case .noResult:
                Circle()
                    .stroke(Color.dimLabel.opacity(0.4), lineWidth: 1)
            }
        }
    }
}
