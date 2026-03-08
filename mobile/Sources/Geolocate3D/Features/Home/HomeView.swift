import SwiftUI

struct HomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RoomStore.self) private var roomStore
    @State private var viewModel = HomeViewModel()

    private var rooms: [RoomRecord] {
        (try? roomStore.fetchAllRooms()) ?? []
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    HomeMapOverviewCard(rooms: Array(rooms))
                        .padding(.horizontal, 20)

                    if rooms.isEmpty {
                        EmptyStateView()
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 20) {
                            ForEach(rooms) { room in
                                RoomPreviewCard(room: room)
                                    .onTapGesture {
                                        coordinator.push(.roomTwin(roomID: room.id))
                                    }
                                    .contextMenu {
                                        Button("Live Search", systemImage: "arkit") {
                                            coordinator.presentImmersive(.liveSearch(roomID: room.id))
                                        }
                                        Button("Query", systemImage: "text.magnifyingglass") {
                                            coordinator.presentSheet(.queryConsole(roomID: room.id))
                                        }
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            viewModel.deleteRoom(room, from: roomStore)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .background(Color.spaceBlack)
            .navigationTitle("Spaces")

            Button {
                coordinator.presentImmersive(.scanRoom)
            } label: {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Color.spatialCyan)
                    .clipShape(Circle())
                    .shadow(color: .spatialCyan.opacity(0.4), radius: 20, y: 8)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search your home like a map.")
                .font(SpatialFont.title)
                .foregroundStyle(.white)
            Text("Find lost objects with room memory, route hints, and live AR guidance.")
                .font(SpatialFont.body)
                .foregroundStyle(.dimLabel)

            HStack(spacing: 12) {
                Button {
                    coordinator.presentSheet(.queryConsole(roomID: nil))
                } label: {
                    Label("Find anything", systemImage: "magnifyingglass")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.spatialCyan, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button {
                    coordinator.presentImmersive(.scanRoom)
                } label: {
                    Label("Add room", systemImage: "plus.viewfinder")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.glassWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(20)
        .glassBackground(cornerRadius: 28)
    }
}
