import SwiftUI

struct RoomPreviewCard: View {
    let room: RoomRecord

    var body: some View {
        VStack(spacing: 0) {
            // Room preview thumbnail
            ZStack {
                if let image = room.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color.voidGray, Color.spaceBlack],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(.dimLabel)
                    }
                }
            }
            .frame(height: 180)
            .clipped()

            // Info section
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(room.name)
                        .font(SpatialFont.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(room.observationCount) objects")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }

                HStack {
                    Text(room.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                    Spacer()
                    StatusChip(status: room.reconstructionStatus.rawValue)
                }
            }
            .padding(16)
            .background(Color.elevatedSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}
