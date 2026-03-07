// DesignSystem/Components/SpatialButton.swift
import SwiftUI

struct SpatialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SpatialFont.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.spatialCyan)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .spatialCyan.opacity(0.4), radius: 20, y: 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
