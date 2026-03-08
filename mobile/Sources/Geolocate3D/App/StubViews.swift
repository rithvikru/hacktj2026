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
            Color.spaceBlack.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arkit")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.spatialCyan.opacity(0.7))
                Text("Live Search")
                    .font(SpatialFont.title2)
                    .foregroundStyle(.white)
                if let roomID {
                    Text("Room: \(roomID.uuidString.prefix(8))")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                }
                Button("Close") {
                    coordinator.dismissFullScreen()
                }
                .font(SpatialFont.subheadline)
                .foregroundStyle(.spatialCyan)
                .padding(.top, 8)
            }
        }
    }
}

struct CompanionTargetStubView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BackendClient.self) private var backendClient

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Companion Target")
                        .font(SpatialFont.title)
                        .foregroundStyle(.white)
                    Text("This surface is reserved for the cooperative target flow. Nearby Interaction and tag-based flows are not wired yet, but the app can still verify backend connectivity from here.")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.dimLabel)
                        .lineSpacing(2)
                }

                VStack(alignment: .leading, spacing: 12) {
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
                .background(Color.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                .font(SpatialFont.subheadline)
                .foregroundStyle(.spatialCyan)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.spaceBlack)
            .task {
                await backendClient.checkConnection()
            }
        }
    }
}

struct RoomTwinStubView: View {
    let roomID: UUID

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.spatialCyan.opacity(0.7))
            Text("Room Twin Viewer")
                .font(SpatialFont.title2)
                .foregroundStyle(.white)
            Text("Room: \(roomID.uuidString.prefix(8))")
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
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
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.inferenceViolet.opacity(0.7))
            Text("Hidden Search")
                .font(SpatialFont.title2)
                .foregroundStyle(.white)
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
            VStack(spacing: 12) {
                Text("Query Console")
                    .font(SpatialFont.title2)
                    .foregroundStyle(.white)
                Text("Where are my keys?")
                    .font(SpatialFont.subheadline)
                    .foregroundStyle(.dimLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.spaceBlack)
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
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        Text(room.name)
                            .font(SpatialFont.title2)
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
                    .font(SpatialFont.subheadline)
                    .foregroundStyle(.spatialCyan)

                    Button("Ask a Query") {
                        dismiss()
                        coordinator.presentSheet(.queryConsole(roomID: roomID))
                    }
                    .font(SpatialFont.subheadline)
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
            .background(Color.spaceBlack)
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
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(observation.label)
                                .font(SpatialFont.title)
                                .foregroundStyle(.white)

                            DetailRow(label: "Confidence", value: "\(Int(observation.confidence * 100))%", valueColor: .spatialCyan)
                            DetailRow(label: "Source", value: observation.source.rawValue)
                            DetailRow(label: "Observed", value: observation.observedAt.formatted(date: .abbreviated, time: .shortened))
                            DetailRow(label: "Visibility", value: observation.visibilityState.rawValue.capitalized)

                            if let roomName = observation.room?.name {
                                DetailRow(label: "Room", value: roomName)
                            }
                        }
                        .padding(20)
                        .background(Color.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.spatialCyan)
                            Text("Loading observation details...")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(Color.spaceBlack)
            .navigationTitle("Object Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.spatialCyan)
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

private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(SpatialFont.subheadline)
                .foregroundStyle(.dimLabel)
            Spacer()
            Text(value)
                .font(SpatialFont.subheadline)
                .foregroundStyle(valueColor)
        }
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
                        .foregroundStyle(.dimLabel)
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
