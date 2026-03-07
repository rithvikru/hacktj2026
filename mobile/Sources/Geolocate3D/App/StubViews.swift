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
    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    Text("Server URL")
                    Text("API Key")
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
}
