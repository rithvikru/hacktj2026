import SwiftUI

struct RoomPreviewCard: View {
    let room: RoomRecord

    var body: some View {
        ZStack(alignment: .bottom) {

            if let image = room.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.3), .spaceBlack],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 8) {
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

                HStack {
                    Text(room.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                    Spacer()
                    StatusChip(status: room.reconstructionStatus.rawValue)
                }
            }
            .padding(20)
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
        .frame(height: 260)
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
