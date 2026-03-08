// DesignSystem/Components/EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.spatialCyan.opacity(0.6), .inferenceViolet.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("No Spaces Yet")
                    .font(SpatialFont.title2)
                    .foregroundStyle(.white)

                Text("Scan your first room to start finding objects")
                    .font(SpatialFont.subheadline)
                    .foregroundStyle(.dimLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
        .padding(.top, 60)
    }
}
