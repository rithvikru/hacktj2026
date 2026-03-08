// DesignSystem/Components/SpatialGlow.swift
import SwiftUI

struct SpatialGlow: ViewModifier {
    var color: Color = .spatialCyan
    var cornerRadius: CGFloat = 20
    var intensity: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(color.opacity(0.25 * intensity), lineWidth: 1)
            }
            .shadow(color: color.opacity(0.08 * intensity), radius: 8, y: 2)
    }
}

extension View {
    func spatialGlow(color: Color = .spatialCyan, cornerRadius: CGFloat = 20,
                     intensity: CGFloat = 1.0) -> some View {
        modifier(SpatialGlow(color: color, cornerRadius: cornerRadius, intensity: intensity))
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool,
                                transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
