import SwiftUI

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Text("Companion Target")
                    .font(.title2)
                    .foregroundStyle(.white)
                Button("Close") { coordinator.dismissFullScreen() }
                    .foregroundStyle(.white)
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

    var body: some View {
        VStack {
            Text("Scan Complete")
                .font(.title2)
            Text("Room saved successfully")
                .foregroundStyle(.secondary)
        }
    }
}

struct ObjectDetailStubView: View {
    let observationID: UUID

    var body: some View {
        VStack {
            Text("Object Detail")
                .font(.title2)
            Text("ID: \(observationID.uuidString.prefix(8))")
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @Environment(WearableStreamSessionManager.self) private var wearableStreamManager
    @Environment(BackendClient.self) private var backendClient
    @AppStorage("activeHomeID") private var activeHomeID = ""
    @AppStorage("backendBaseURL") private var backendBaseURL = BackendClient.defaultBaseURLString
    @AppStorage("wearableBridgeMode") private var wearableBridgeMode = WearableBridgeMode.meta.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    TextField("Server URL", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    LabeledContent("Active Base URL") {
                        Text(backendClient.baseURL.absoluteString)
                            .lineLimit(2)
                            .font(.caption)
                    }
                    LabeledContent("Connection") {
                        Text(backendClient.isConnected ? "Connected" : "Disconnected")
                    }
                    Button("Apply Backend URL") {
                        guard let url = URL(string: backendBaseURL) else {
                            wearableStreamManager.lastErrorMessage = "Invalid backend URL."
                            return
                        }
                        backendClient.updateBaseURL(url)
                        Task {
                            await backendClient.checkConnection()
                        }
                    }
                    Button("Check Backend Connection") {
                        Task {
                            await backendClient.checkConnection()
                        }
                    }
                }
                Section("Wearables") {
                    Picker("Wearable Mode", selection: $wearableBridgeMode) {
                        ForEach(WearableBridgeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .onChange(of: wearableBridgeMode) { _, newValue in
                        wearableStreamManager.setBridgeMode(WearableBridgeMode.fromStoredValue(newValue))
                        wearableStreamManager.configureIfNeeded()
                    }
                    LabeledContent("Active Home") {
                        Text(activeHomeID.isEmpty ? "Not created" : String(activeHomeID.prefix(8)))
                    }
                    LabeledContent("Mode") {
                        Text(WearableBridgeMode.fromStoredValue(wearableBridgeMode).displayName)
                    }
                    LabeledContent("Session ID") {
                        Text(wearableStreamManager.activeSessionID.map { String($0.prefix(8)) } ?? "None")
                    }
                    LabeledContent("Registration") {
                        Text(registrationLabel)
                    }
                    LabeledContent("Streaming") {
                        Text(streamLabel)
                    }
                    LabeledContent("Backend Status") {
                        Text(wearableStreamManager.latestBackendSessionStatus ?? "Unknown")
                    }
                    LabeledContent("Local Frames") {
                        Text("\(wearableStreamManager.localPersistedFrameCount)")
                    }
                    LabeledContent("Backend Frames") {
                        Text("\(wearableStreamManager.backendFrameCount)")
                    }
                    if let latestSessionStoragePath = wearableStreamManager.latestSessionStoragePath {
                        LabeledContent("Storage Path") {
                            Text(latestSessionStoragePath)
                                .lineLimit(2)
                                .font(.caption)
                        }
                    }
                    if let lastErrorMessage = wearableStreamManager.lastErrorMessage {
                        LabeledContent("Last Error") {
                            Text(lastErrorMessage)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                    Button("Create Active Home") {
                        Task {
                            do {
                                if activeHomeID.isEmpty {
                                    activeHomeID = try await backendClient.createHome(name: "My Home")
                                }
                            } catch {
                                print("Failed to create home: \(error.localizedDescription)")
                            }
                        }
                    }
                    .disabled(!activeHomeID.isEmpty)
                    Button(registerButtonTitle) {
                        Task {
                            await wearableStreamManager.beginRegistration()
                        }
                    }
                    .disabled(isRegisterDisabled)
                    Button("Start Wearable Stream") {
                        Task {
                            await wearableStreamManager.startStreaming(homeID: activeHomeID)
                        }
                    }
                    .disabled(activeHomeID.isEmpty || isStreamButtonDisabled)
                    Button("Stop Wearable Stream", role: .destructive) {
                        Task {
                            await wearableStreamManager.stopStreaming()
                        }
                    }
                    .disabled(!isStopEnabled)
                    Button("Refresh Wearable Session") {
                        Task {
                            await wearableStreamManager.refreshActiveSession()
                        }
                    }
                    .disabled(wearableStreamManager.activeSessionID == nil)
                }
                Section("Detection") {
                    Text("Model Selection")
                    Text("Detection FPS")
                }
                Section("About") {
                    Text("Geolocate3D v0.1")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var registrationLabel: String {
        switch wearableStreamManager.registrationState {
        case .unconfigured:
            return "Unconfigured"
        case .configured:
            return "Configured"
        case .registrationRequired:
            return "Registration Required"
        case .registering:
            return "Registering"
        case .registered:
            return "Registered"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private var streamLabel: String {
        switch wearableStreamManager.streamState {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting"
        case .streaming:
            return "Streaming"
        case .degraded:
            return "Degraded"
        case .reconnecting:
            return "Reconnecting"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private var isRegisterDisabled: Bool {
        switch wearableStreamManager.registrationState {
        case .registering, .registered:
            return true
        default:
            return false
        }
    }

    private var isStreamButtonDisabled: Bool {
        switch wearableStreamManager.streamState {
        case .connecting, .streaming, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var registerButtonTitle: String {
        switch WearableBridgeMode.fromStoredValue(wearableBridgeMode) {
        case .meta:
            return "Register Ray-Ban Meta"
        case .simulated:
            return "Enable Simulated Stream"
        }
    }

    private var isStopEnabled: Bool {
        switch wearableStreamManager.streamState {
        case .connecting, .streaming, .reconnecting, .degraded, .paused:
            return true
        default:
            return false
        }
    }
}
