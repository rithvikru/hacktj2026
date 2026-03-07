// DesignSystem/Components/GlassCard.swift
import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 32
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
    }
}
