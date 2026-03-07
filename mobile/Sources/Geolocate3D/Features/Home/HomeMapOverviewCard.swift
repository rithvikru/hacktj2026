import SwiftUI

struct HomeMapOverviewCard: View {
    let rooms: [RoomRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Home Memory Map")
                        .font(SpatialFont.headline)
                        .foregroundStyle(.white)
                    Text("Route across saved rooms, then hand off to AR in the target space.")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }
                Spacer()
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.spatialCyan)
            }

            if rooms.isEmpty {
                Text("Scan at least one room to start building a navigable home graph.")
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(rooms.prefix(4))) { room in
                        roomNode(for: room)
                    }
                    if rooms.count > 4 {
                        Text("+\(rooms.count - 4)")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                }

                Text(routePreview)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.spatialCyan)
            }
        }
        .padding(20)
        .glassBackground(cornerRadius: 28)
    }

    private func roomNode(for room: RoomRecord) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(room.reconstructionStatus == .complete ? Color.spatialCyan : Color.warningAmber.opacity(0.9))
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                }

            Text(room.name)
                .font(SpatialFont.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if room.id != rooms.prefix(4).last?.id {
                Capsule()
                    .fill(Color.glassEdge)
                    .frame(width: 28, height: 2)
                    .offset(x: 18, y: -10)
            }
        }
    }

    private var routePreview: String {
        let names = rooms.prefix(3).map(\.name)
        guard !names.isEmpty else {
            return "No route available yet."
        }
        return "Route preview: " + names.joined(separator: " -> ")
    }
}
