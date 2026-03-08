import SwiftUI

struct LayerToggleBar: View {
    @Binding var showScaffold: Bool
    @Binding var showObjects: Bool
    @Binding var showHeatmap: Bool
    @Binding var showDense: Bool

    var body: some View {
        HStack(spacing: 4) {
            LayerToggleButton(icon: "square.stack.3d.up", label: "Scaffold",
                              isOn: $showScaffold)
            LayerToggleButton(icon: "cube", label: "Objects",
                              isOn: $showObjects)
            LayerToggleButton(icon: "flame", label: "Heatmap",
                              isOn: $showHeatmap)
            LayerToggleButton(icon: "cloud.fill", label: "Dense",
                              isOn: $showDense)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
        .padding(.horizontal, 24)
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
            .foregroundStyle(isOn ? .white : .dimLabel)
            .frame(width: 64, height: 48)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.spatialCyan.opacity(0.2))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.spatialCyan.opacity(0.4), lineWidth: 0.5)
                        }
                }
            }
        }
    }
}
