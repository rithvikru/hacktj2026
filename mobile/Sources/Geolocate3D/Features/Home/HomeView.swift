import SwiftUI

struct HomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RoomStore.self) private var roomStore
    @State private var viewModel = HomeViewModel()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("preferredMode") private var preferredMode = ""
    @State private var skipScan = false

    private var showEmptyState: Bool {
        roomStore.rooms.isEmpty && !skipScan && preferredMode != "outside"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    if showEmptyState {

                        EmptyStateScanCTA(onScan: {
                            coordinator.presentImmersive(.scanRoom)
                        })
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    } else {

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Spaces")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
                            ForEach(roomStore.rooms) { room in
                                RoomPreviewCard(
                                    room: room,
                                    onSearch: {
                                        coordinator.presentImmersive(.liveSearch(roomID: room.id))
                                    },
                                    onQuery: {
                                        coordinator.presentSheet(.queryConsole(roomID: room.id))
                                    },
                                    onTwin: {
                                        coordinator.push(.roomTwin(roomID: room.id))
                                    },
                                    onDelete: {
                                        viewModel.deleteRoom(room, from: roomStore)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)

                        Button {
                            coordinator.presentImmersive(.scanRoom)
                        } label: {
                            Text("Scan another room")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.zinc900, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)

                    HomeMapOverviewCard(rooms: Array(rooms))
                        .padding(.horizontal, 16)
                }

                UnifiedDeviceCard()
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
            .background(Color.spaceBlack)
            .navigationTitle("Uncover")

            if showEmptyState {
                HStack {
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    Spacer()
                    Button {
                        skipScan = true
                    } label: {
                        Text("Skip for now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    private var rooms: [RoomRecord] {
        (try? roomStore.fetchAllRooms()) ?? []
    }
}

private struct EmptyStateScanCTA: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)

            VStack(spacing: 12) {
                Text("Scan a room to start\nfinding things")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Walk around a room with your camera to build a 3D map. Then search for anything.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button(action: onScan) {
                Text("Start Scanning")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.spatialCyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
