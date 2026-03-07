import SwiftUI

struct ConfidenceIndicator: View {
    let level: DetectionConfidenceClass
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch level {
            case .confirmedHigh:
                Circle()
                    .stroke(Color.spatialCyan, lineWidth: 3)
                    .shadow(color: .spatialCyan.opacity(0.6), radius: 8)
                    .overlay { Circle().fill(.spatialCyan.opacity(0.3)).scaleEffect(0.3) }

            case .confirmedMedium:
                Circle()
                    .stroke(Color.spatialCyan.opacity(0.7), lineWidth: 2)

            case .lastSeen:
                Circle()
                    .stroke(Color.warningAmber, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.4 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }

            case .signalEstimated:
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.signalMagenta, lineWidth: 2)
                    .rotationEffect(.degrees(pulse ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }

            case .likelihoodRanked:
                ZStack {
                    AngularGradient(
                        colors: [.inferenceViolet, .spatialCyan.opacity(0.5), .inferenceViolet],
                        center: .center
                    )
                    .blur(radius: 12)
                    RadialGradient(
                        colors: [.white.opacity(0.6), .clear],
                        center: .center, startRadius: 0, endRadius: 12
                    )
                    .blendMode(.plusLighter)
                }
                .clipShape(Circle())
                .scaleEffect(pulse ? 1.05 : 0.95)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            case .staleMemory:
                Circle()
                    .stroke(Color.warningAmber.opacity(0.4), lineWidth: 2)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.warningAmber)
                    }

            case .noResult:
                Circle()
                    .stroke(Color.dimLabel, lineWidth: 1)
            }
        }
    }
}
