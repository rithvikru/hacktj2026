import SwiftUI

struct OutdoorCaptureView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(LocationService.self) private var locationService
    @Environment(OutdoorSessionStore.self) private var store
    @Environment(WearableStreamSessionManager.self) private var wearableManager
    @State private var viewModel = OutdoorMapViewModel()

    var body: some View {
        ZStack {
            Color.spaceBlack.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: viewModel.isCapturing ? "antenna.radiowaves.left.and.right" : "camera.viewfinder")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.spatialCyan)

                VStack(spacing: 8) {
                    Text(viewModel.isCapturing ? "Capturing" : "Ready to Capture")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    if viewModel.isCapturing {
                        Text("\(store.currentSession?.frameCount ?? 0) frames captured")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.dimLabel)
                    } else if let error = viewModel.captureError {
                        Text(error)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.warningAmber)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Start walking with your glasses on")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.dimLabel)
                    }

                    if let device = wearableManager.connectedDeviceName {
                        HStack(spacing: 6) {
                            Image(systemName: "eyeglasses")
                                .foregroundStyle(.confirmGreen)
                            Text(device)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.dimLabel)
                        }
                    } else if case .registered = wearableManager.registrationState {
                        HStack(spacing: 6) {
                            Image(systemName: "eyeglasses")
                                .foregroundStyle(.dimLabel)
                            Text("Glasses registered")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.dimLabel)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "eyeglasses")
                                .foregroundStyle(.warningAmber)
                            Text("Glasses not connected")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.warningAmber)
                        }
                    }
                }

                if let loc = locationService.currentLocation {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.confirmGreen)
                        Text(String(format: "GPS: ±%.0fm", loc.horizontalAccuracy))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.dimLabel)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "location.slash")
                            .foregroundStyle(.warningAmber)
                        Text("Acquiring GPS...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.warningAmber)
                    }
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        if viewModel.isCapturing {
                            viewModel.stopCapture(wearableManager: wearableManager, store: store)
                        } else {
                            viewModel.startCapture(
                                wearableManager: wearableManager,
                                store: store,
                                locationService: locationService
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.isCapturing ? "stop.fill" : "record.circle")
                                .font(.system(size: 20))
                            Text(viewModel.isCapturing ? "Stop Capture" : "Start Capture")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(viewModel.isCapturing ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(viewModel.isCapturing ? Color.red : .spatialCyan)
                        .clipShape(Capsule())
                    }

                    Button("Close") {
                        if viewModel.isCapturing {
                            viewModel.stopCapture(wearableManager: wearableManager, store: store)
                        }
                        coordinator.dismissFullScreen()
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.dimLabel)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            locationService.startUpdating()
        }
    }
}
