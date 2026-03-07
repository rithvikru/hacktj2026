import SwiftUI

struct LayerToggleBar: View {
    @Binding var showScaffold: Bool
    @Binding var showObjects: Bool
    @Binding var showHeatmap: Bool
    @Binding var showDense: Bool

    var body: some View {
        HStack(spacing: 12) {
            LayerToggleButton(icon: "square.stack.3d.up", label: "Scaffold",
                              isOn: $showScaffold)
            LayerToggleButton(icon: "cube", label: "Objects",
                              isOn: $showObjects)
            LayerToggleButton(icon: "flame", label: "Heatmap",
                              isOn: $showHeatmap)
            LayerToggleButton(icon: "cloud.fill", label: "Dense",
                              isOn: $showDense)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}

private struct LayerToggleButton: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(SpatialFont.dataSmall)
            }
            .foregroundStyle(isOn ? .spatialCyan : .dimLabel)
            .frame(width: 56, height: 44)
        }
    }
}
