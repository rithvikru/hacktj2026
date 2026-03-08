import SwiftUI
import RoomPlan
import AVFoundation

struct ScanRoomView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RoomStore.self) private var roomStore
    @Environment(SpatialSessionManager.self) private var spatialSessionManager
    @State private var viewModel = ScanViewModel()
    @State private var cameraAuthorized = false
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            if cameraAuthorized {
                RoomCaptureViewRepresentable(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                if let cameraError {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(cameraError)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Go to Settings > Privacy & Security > Camera and enable Geolocate3D")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.spatialCyan)
                    }
                    .padding(40)
                }
            }

            VStack {
                HStack {
                    Button(action: { coordinator.dismissFullScreen() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if cameraAuthorized {
                        ScanStatusPill(state: viewModel.scanState)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                if cameraAuthorized {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(viewModel.detectedObjectCount)")
                                .font(SpatialFont.dataLarge)
                                .foregroundStyle(.spatialCyan)
                            Text("objects detected")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                        }
                        Spacer()
                        if viewModel.scanState == .ready {
                            Button("Save Room") {
                                Task { await viewModel.finalizeScan(roomStore: roomStore) }
                            }
                            .buttonStyle(SpatialButtonStyle())
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .task {

            spatialSessionManager.tearDown()
            await requestCameraAccess()
        }
        .onChange(of: viewModel.savedRoomID) { _, roomID in
            if let roomID {
                coordinator.finishScanAndShowTwin(roomID: roomID)
            }
        }
    }

    private func requestCameraAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorized = granted
            if !granted {
                cameraError = "Camera access denied"
            }
        case .denied, .restricted:
            cameraError = "Camera access denied"
        @unknown default:
            cameraError = "Camera access unavailable"
        }

        if cameraAuthorized && !RoomCaptureSession.isSupported {
            cameraAuthorized = false
            cameraError = "RoomPlan is not supported on this device"
        }
    }
}
