import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoomRecord.updatedAt, order: .reverse) private var rooms: [RoomRecord]
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if rooms.isEmpty {
                    EmptyStateView()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(rooms) { room in
                            RoomPreviewCard(room: room)
                                .onTapGesture {
                                    coordinator.push(.roomTwin(roomID: room.id))
                                }
                                .contextMenu {
                                    Button("Live Search", systemImage: "arkit") {
                                        coordinator.presentImmersive(.liveSearch(roomID: room.id, target: nil))
                                    }
                                    Button("Query", systemImage: "text.magnifyingglass") {
                                        coordinator.presentSheet(.queryConsole(roomID: room.id))
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        viewModel.deleteRoom(room, from: modelContext)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.spaceBlack)
            .navigationTitle("Spaces")

            // Floating scan button
            Button {
                coordinator.presentImmersive(.scanRoom)
            } label: {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.spatialCyan)
                    .clipShape(Circle())
                    .shadow(color: .spatialCyan.opacity(0.2), radius: 16, y: 6)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
    }
}
