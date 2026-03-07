import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.dimLabel)
                .symbolRenderingMode(.hierarchical)

            Text("No Spaces Yet")
                .font(SpatialFont.title2)
                .foregroundStyle(.white)

            Text("Tap the scan button to capture your first room")
                .font(SpatialFont.subheadline)
                .foregroundStyle(.dimLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}
