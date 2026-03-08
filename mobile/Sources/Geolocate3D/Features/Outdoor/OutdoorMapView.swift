import SwiftUI
import MapKit

struct OutdoorMapView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(LocationService.self) private var locationService
    @Environment(OutdoorSessionStore.self) private var store
    @Environment(WearableStreamSessionManager.self) private var wearableManager
    @State private var viewModel = OutdoorMapViewModel()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedDetection: OutdoorDetection?

    var body: some View {
        ZStack(alignment: .bottom) {

            Map(position: $cameraPosition, selection: $selectedDetection) {
                UserAnnotation()

                ForEach(viewModel.clusteredDetections(from: store.detections)) { detection in
                    Annotation(
                        detection.label,
                        coordinate: detection.coordinate,
                        anchor: .bottom
                    ) {
                        DetectionAnnotationView(detection: detection)
                    }
                    .tag(detection)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.cafe, .restaurant, .parking])))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {

                FloatingQueryBar { query in
                    viewModel.searchQuery = query
                    Task {
                        await viewModel.performSearch(query: query, store: store)
                    }
                }

                CaptureStatusBar(
                    isCapturing: viewModel.isCapturing,
                    frameCount: store.currentSession?.frameCount ?? 0,
                    duration: store.currentSession?.duration ?? 0
                ) {
                    if viewModel.isCapturing {
                        viewModel.stopCapture(wearableManager: wearableManager, store: store)
                    } else {
                        viewModel.startCapture(
                            wearableManager: wearableManager,
                            store: store,
                            locationService: locationService
                        )
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .navigationTitle("Explore")
        .onChange(of: selectedDetection) { _, detection in
            if let detection {
                coordinator.presentSheet(.framePreview(detectionID: detection.id))
                selectedDetection = nil
            }
        }
        .onAppear {
            locationService.requestAuthorization()
            locationService.startUpdating()
        }
    }
}

private struct CaptureStatusBar: View {
    let isCapturing: Bool
    let frameCount: Int
    let duration: TimeInterval
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if isCapturing {

                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .modifier(PulseModifier())

                    Text(formatDuration(duration))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("\(frameCount) frames")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.dimLabel)
                }
            }

            Spacer()

            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isCapturing ? "stop.fill" : "record.circle")
                        .font(.system(size: 18, weight: .medium))
                    Text(isCapturing ? "Stop" : "Start Capture")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(isCapturing ? .white : .black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isCapturing ? Color.red.opacity(0.8) : .spatialCyan)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
