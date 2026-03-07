import SwiftData
import SwiftUI

struct ScanResultsView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var room: RoomRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.confirmGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room Saved")
                        .font(SpatialFont.title2)
                        .foregroundStyle(.white)
                    Text(room?.name ?? "Spatial memory updated")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }
            }

            detailCard(
                title: "What happened",
                body: "The room scan, frame bundle, and world map were saved. You can open the room twin, start search immediately, or keep scanning the rest of the home."
            )

            if let room {
                detailCard(
                    title: "Current state",
                    body: "\(room.observationCount) observations • \(room.reconstructionStatus.rawValue.capitalized) reconstruction"
                )
            }

            HStack(spacing: 12) {
                Button {
                    coordinator.dismissSheet()
                    coordinator.push(.roomTwin(roomID: roomID))
                } label: {
                    Label("Open Twin", systemImage: "cube.transparent")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.spatialCyan, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button {
                    coordinator.dismissSheet()
                    coordinator.presentImmersive(.liveSearch(roomID: roomID))
                } label: {
                    Label("Search", systemImage: "arkit")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.glassWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(20)
        .background(Color.obsidian)
        .task {
            loadRoom()
        }
    }

    private func detailCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
            Text(body)
                .font(SpatialFont.body)
                .foregroundStyle(.white)
        }
        .padding(16)
        .glassBackground(cornerRadius: 20)
    }

    private func loadRoom() {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == roomID }
        )
        descriptor.fetchLimit = 1
        room = try? modelContext.fetch(descriptor).first
    }
}
