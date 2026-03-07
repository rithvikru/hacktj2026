import SwiftUI
import SwiftData
import UIKit

// MARK: - Stub Views for Navigation Skeleton
// These are temporary placeholders replaced by real implementations in later phases.

// HomeStubView and ScanRoomView removed — real implementations in Features/Home/ and Features/Scan/

struct LiveSearchStubView: View {
    let roomID: UUID?
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "arkit")
                    .font(.system(size: 48))
                    .foregroundStyle(.spatialCyan)
                Text("Live Search")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if let roomID {
                    Text("Room: \(roomID.uuidString.prefix(8))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Close") {
                    coordinator.dismissFullScreen()
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct CompanionTargetStubView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BackendClient.self) private var backendClient

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Companion Target")
                        .font(SpatialFont.title)
                        .foregroundStyle(.white)
                    Text("This surface is reserved for the cooperative target flow. Nearby Interaction and tag-based flows are not wired yet, but the app can still verify backend connectivity from here.")
                        .font(SpatialFont.body)
                        .foregroundStyle(.dimLabel)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        backendClient.isConnected ? "Backend reachable" : "Backend not reachable",
                        systemImage: backendClient.isConnected ? "checkmark.circle.fill" : "wifi.slash"
                    )
                    .foregroundStyle(backendClient.isConnected ? .confirmGreen : .warningAmber)

                    Text(backendClient.baseURLString)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.dimLabel)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Button("Re-test Backend") {
                    Task {
                        await backendClient.checkConnection()
                    }
                }
                .buttonStyle(SpatialButtonStyle())

                Spacer()

                Button("Close") {
                    coordinator.dismissFullScreen()
                }
                .foregroundStyle(.white)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.obsidian)
            .task {
                await backendClient.checkConnection()
            }
        }
    }
}

struct RoomTwinStubView: View {
    let roomID: UUID

    var body: some View {
        VStack {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.spatialCyan)
            Text("Room Twin Viewer")
                .font(.title2.weight(.semibold))
            Text("Room: \(roomID.uuidString.prefix(8))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.spaceBlack)
        .navigationTitle("Room Twin")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HiddenSearchStubView: View {
    let roomID: UUID

    var body: some View {
        VStack {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundStyle(.inferenceViolet)
            Text("Hidden Search")
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.spaceBlack)
        .navigationTitle("Hidden Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct QueryConsoleStubView: View {
    let roomID: UUID?

    var body: some View {
        NavigationStack {
            VStack {
                Text("Query Console")
                    .font(.title2)
                Text("Where are my keys?")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Query")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ScanResultsStubView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var room: RoomRecord?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let room {
                    if let image = room.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        Text(room.name)
                            .font(SpatialFont.title)
                            .foregroundStyle(.white)
                        Text("\(room.observationCount) observations saved")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                        StatusChip(status: room.reconstructionStatus.rawValue)
                    }

                    Button("Open Room Twin") {
                        dismiss()
                        coordinator.push(.roomTwin(roomID: roomID))
                    }
                    .buttonStyle(SpatialButtonStyle())

                    Button("Start Live Search") {
                        dismiss()
                        coordinator.presentImmersive(.liveSearch(roomID: roomID))
                    }
                    .foregroundStyle(.spatialCyan)

                    Button("Ask a Query") {
                        dismiss()
                        coordinator.presentSheet(.queryConsole(roomID: roomID))
                    }
                    .foregroundStyle(.spatialCyan)
                } else {
                    ProgressView()
                        .tint(.spatialCyan)
                    Text("Loading room summary...")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }
                Spacer()
            }
            .padding(24)
            .background(Color.obsidian)
            .navigationTitle("Scan Complete")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                room = fetchRoom()
            }
        }
    }

    private func fetchRoom() -> RoomRecord? {
        var descriptor = FetchDescriptor<RoomRecord>(predicate: #Predicate { $0.id == roomID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

struct ObjectDetailStubView: View {
    let observationID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var observation: ObjectObservation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let observation {
                        if let snapshotPath = observation.snapshotPath,
                           let image = UIImage(contentsOfFile: snapshotPath) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(observation.label)
                                .font(SpatialFont.title)
                                .foregroundStyle(.white)
                            HStack {
                                Text("Confidence")
                                    .foregroundStyle(.dimLabel)
                                Spacer()
                                Text("\(Int(observation.confidence * 100))%")
                                    .foregroundStyle(.spatialCyan)
                            }
                            HStack {
                                Text("Source")
                                    .foregroundStyle(.dimLabel)
                                Spacer()
                                Text(observation.source.rawValue)
                                    .foregroundStyle(.white)
                            }
                            HStack {
                                Text("Observed")
                                    .foregroundStyle(.dimLabel)
                                Spacer()
                                Text(observation.observedAt.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.white)
                            }
                            HStack {
                                Text("Visibility")
                                    .foregroundStyle(.dimLabel)
                                Spacer()
                                Text(observation.visibilityState.rawValue.capitalized)
                                    .foregroundStyle(.white)
                            }
                            if let roomName = observation.room?.name {
                                HStack {
                                    Text("Room")
                                        .foregroundStyle(.dimLabel)
                                    Spacer()
                                    Text(roomName)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        ProgressView()
                            .tint(.spatialCyan)
                        Text("Loading observation details...")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                }
                .padding(24)
            }
            .background(Color.obsidian)
            .navigationTitle("Object Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                observation = fetchObservation()
            }
        }
    }

    private func fetchObservation() -> ObjectObservation? {
        var descriptor = FetchDescriptor<ObjectObservation>(predicate: #Predicate { $0.id == observationID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

struct SettingsView: View {
    @Environment(BackendClient.self) private var backendClient
    @State private var baseURLText = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    TextField("http://192.168.1.10:8000", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Backend URL") {
                        saveBackendURL()
                    }
                    Button("Reset To Default") {
                        backendClient.resetBaseURL()
                        baseURLText = backendClient.baseURLString
                        statusMessage = "Backend URL reset to default."
                    }
                    Button("Test Connection") {
                        Task {
                            await backendClient.checkConnection()
                            statusMessage = backendClient.isConnected
                                ? "Backend is reachable."
                                : "Backend is not reachable from this device."
                        }
                    }
                    Text("Current: \(backendClient.baseURLString)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.dimLabel)
                }
                Section("Status") {
                    Label(
                        backendClient.isConnected ? "Connected" : "Disconnected",
                        systemImage: backendClient.isConnected ? "checkmark.circle.fill" : "wifi.slash"
                    )
                    .foregroundStyle(backendClient.isConnected ? .confirmGreen : .warningAmber)
                    if let statusMessage {
                        Text(statusMessage)
                            .foregroundStyle(.dimLabel)
                    }
                }
                Section("Device Notes") {
                    Text("Use your Mac or server LAN IP for physical iPhone testing. `localhost` only works for simulator or on-device backend setups.")
                        .foregroundStyle(.dimLabel)
                }
                Section("About") {
                    Text("Geolocate3D")
                    Text("AR room scanning, query, hidden search, and dense twin viewer")
                }
            }
            .navigationTitle("Settings")
            .task {
                baseURLText = backendClient.baseURLString
                await backendClient.checkConnection()
            }
        }
    }

    private func saveBackendURL() {
        do {
            try backendClient.updateBaseURL(baseURLText)
            statusMessage = "Backend URL saved."
        } catch {
            statusMessage = "Invalid backend URL."
        }
    }
}
