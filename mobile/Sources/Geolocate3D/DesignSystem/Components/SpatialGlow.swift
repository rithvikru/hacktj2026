import SwiftUI

struct SpatialGlow: ViewModifier {
    var color: Color = .spatialCyan
    var cornerRadius: CGFloat = 24
    var intensity: CGFloat = 1.0

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi) + 1) / 2

            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(color.opacity(0.1 + (phase * 0.15 * intensity)))
                        .blur(radius: 12 + (phase * 8))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            color.opacity(0.4 + (phase * 0.4 * intensity)),
                            lineWidth: 1 + (phase * 1.5)
                        )
                        .blendMode(.plusLighter)
                }
        }
    }
}

extension View {
    func spatialGlow(color: Color = .spatialCyan, cornerRadius: CGFloat = 24,
                     intensity: CGFloat = 1.0) -> some View {
        modifier(SpatialGlow(color: color, cornerRadius: cornerRadius, intensity: intensity))
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool,
                                transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
