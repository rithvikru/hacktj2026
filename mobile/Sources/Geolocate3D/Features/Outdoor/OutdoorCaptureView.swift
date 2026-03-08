import SwiftUI

struct OutdoorCaptureView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(LocationService.self) private var locationService
    @Environment(OutdoorSessionStore.self) private var store
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
                    } else {
                        Text("Start walking with your glasses on")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.dimLabel)
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
                            viewModel.stopCapture(store: store)
                        } else {
                            viewModel.startCapture(store: store, locationService: locationService)
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
                            viewModel.stopCapture(store: store)
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
