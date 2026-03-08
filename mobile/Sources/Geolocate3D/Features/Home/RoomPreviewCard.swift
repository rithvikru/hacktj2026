import SwiftUI

struct RoomPreviewCard: View {
    let room: RoomRecord
    var onSearch: () -> Void = {}
    var onQuery: () -> Void = {}
    var onTwin: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {

            ZStack(alignment: .topTrailing) {
                if let image = room.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [.indigo.opacity(0.3), .spaceBlack],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 180)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                StatusChip(status: room.reconstructionStatus.rawValue)
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text(room.name)
                        .font(SpatialFont.title2)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(room.observationCount) objects")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1), in: Capsule())
                }

                Text(room.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)

                HStack(spacing: 8) {
                    ActionPill(icon: "arkit", label: "Search", action: onSearch)
                    ActionPill(icon: "text.magnifyingglass", label: "Query", action: onQuery)
                    ActionPill(icon: "cube.transparent", label: "Twin", action: onTwin)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.dimLabel)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.06), in: Circle())
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
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

private struct ActionPill: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(SpatialFont.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
        }
    }
}
