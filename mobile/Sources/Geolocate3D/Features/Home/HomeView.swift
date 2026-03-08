import SwiftUI

struct HomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RoomStore.self) private var roomStore
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                DeviceCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                WearablesStatusCard()
                    .padding(.horizontal, 16)

                HomeMapOverviewCard(rooms: Array(rooms))
                    .padding(.horizontal, 16)

                if !roomStore.rooms.isEmpty {
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
                    }
                }

                AISuggestionSection(onSelect: { suggestion in
                    coordinator.presentSheet(.queryConsole(roomID: nil))
                })

                if roomStore.rooms.isEmpty {
                    Button {
                        coordinator.presentImmersive(.scanRoom)
                    } label: {
                        Label("Scan Your First Room", systemImage: "viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.spatialCyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.spaceBlack)
        .navigationTitle("Uncover")
    }

    private var rooms: [RoomRecord] {
        (try? roomStore.fetchAllRooms()) ?? []
    }
}

private struct DeviceCard: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(WearableStreamSessionManager.self) private var wearableManager

    var body: some View {
        VStack(spacing: 0) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(deviceName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: connectionIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(connectionColor.opacity(0.7))
                        Text(connectionLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()

                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Image(systemName: "eyeglasses")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            HStack {
                HStack(spacing: 8) {
                    Text("Ray-Ban")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.4))
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 1, height: 14)
                    Image(systemName: "infinity")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Meta")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    coordinator.selectedTab = 1
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.zinc900, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var deviceName: String {
        wearableManager.connectedDeviceName ?? "Ray-Ban Meta"
    }

    private var connectionColor: Color {
        if wearableManager.isStreamingActive { return .spatialCyan }
        if case .registered = wearableManager.registrationState { return .confirmGreen }
        if case .failed = wearableManager.registrationState { return .red }
        if case .failed = wearableManager.streamState { return .red }
        return .warningAmber
    }

    private var connectionLabel: String {
        if wearableManager.isStreamingActive { return "Streaming" }
        switch wearableManager.registrationState {
        case .registered: return "Connected"
        case .registering: return "Registering..."
        case .registrationRequired: return "Not Registered"
        case .failed: return "Error"
        default: return "Not Configured"
        }
    }

    private var connectionIcon: String {
        if wearableManager.isStreamingActive { return "wave.3.right" }
        switch wearableManager.registrationState {
        case .registered: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        default: return "circle.dotted"
        }
    }
}

private struct AISuggestionSection: View {
    let onSelect: (String) -> Void

    private let suggestions = [
        ("magnifyingglass", "Find my keys"),
        ("wallet.bifold", "Where did I leave my wallet?"),
        ("desktopcomputer", "Show me what's on my desk"),
        ("sofa", "Search the living room"),
        ("door.left.hand.open", "What objects are near the door?"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("What can I do for you?")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 10) {
                ForEach(suggestions, id: \.1) { icon, text in
                    Button {
                        onSelect(text)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.spatialCyan)
                                .frame(width: 48, height: 48)
                                .background(Color.spatialCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(text)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.zinc900, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
