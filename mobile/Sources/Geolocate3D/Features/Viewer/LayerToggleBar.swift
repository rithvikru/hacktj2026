import SwiftUI

struct LayerToggleBar: View {
    @Binding var viewerMode: ViewerMode
    @Binding var showLabels: Bool
    @Binding var showSearchHits: Bool
    @Binding var showHypotheses: Bool
    let onModeChanged: (ViewerMode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Secondary toggle chips
            HStack(spacing: 6) {
                ToggleChip(label: "Labels", isOn: $showLabels)
                ToggleChip(label: "Search Hits", isOn: $showSearchHits)
                ToggleChip(label: "Hypotheses", isOn: $showHypotheses)
            }

            // Primary segmented control
            HStack(spacing: 0) {
                ForEach(ViewerMode.allCases, id: \.rawValue) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            viewerMode = mode
                            onModeChanged(mode)
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(SpatialFont.caption)
                            .foregroundStyle(viewerMode == mode ? .white : .dimLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                viewerMode == mode
                                    ? Color.spatialCyan.opacity(0.25)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                }
            }
            .padding(3)
            .background(Color.elevatedSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 20)
    }
}

private struct ToggleChip: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        } label: {
            Text(label)
                .font(SpatialFont.caption)
                .foregroundStyle(isOn ? .white : .dimLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isOn ? Color.spatialCyan.opacity(0.15) : Color.elevatedSurface.opacity(0.7),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isOn ? Color.spatialCyan.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}
