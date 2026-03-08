import SwiftUI
import RoomPlan
import SwiftData

struct ScanRoomView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BackendClient.self) private var backendClient
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScanViewModel()

    var body: some View {
        ZStack {
            RoomCaptureViewRepresentable(viewModel: viewModel, backendClient: backendClient)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ForEach(viewModel.liveSpotlightDetections) { detection in
                    ScanObjectOverlay(detection: detection, canvasSize: proxy.size)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: { coordinator.dismissFullScreen() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Spacer()
                    ScanStatusPill(state: viewModel.scanState)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Bottom bar
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.detectedObjectCount)")
                            .font(SpatialFont.dataLarge)
                            .foregroundStyle(.white)
                        Text("room features")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                    if !viewModel.liveSpotlightDetections.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.liveSpotlightDetections.count)")
                                .font(SpatialFont.dataLarge)
                                .foregroundStyle(.warningAmber)
                            Text("AI spotlights")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                        }
                        .padding(.leading, 16)
                    }
                    Spacer()
                    if viewModel.scanState == .scanning {
                        Button("Stop Scan") {
                            viewModel.stopSession()
                        }
                        .buttonStyle(SecondarySpatialButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                    if viewModel.scanState == .ready {
                        Button("Save Room") {
                            Task {
                                await viewModel.finalizeScan(
                                    modelContext: modelContext,
                                    backendClient: backendClient
                                )
                            }
                        }
                        .buttonStyle(SpatialButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.clear, Color.spaceBlack.opacity(0.8), Color.spaceBlack],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onChange(of: viewModel.savedRoomID) { _, roomID in
            if let roomID {
                coordinator.finishScanAndShowTwin(roomID: roomID)
            }
        }
    }
}

private struct ScanObjectOverlay: View {
    let detection: ScanSpotlightDetection
    let canvasSize: CGSize

    private var rect: CGRect {
        CGRect(
            x: detection.viewportRectNormalized.minX * canvasSize.width,
            y: detection.viewportRectNormalized.minY * canvasSize.height,
            width: detection.viewportRectNormalized.width * canvasSize.width,
            height: detection.viewportRectNormalized.height * canvasSize.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(borderColor.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(borderColor)
                        .frame(width: 6, height: 6)
                    Text(detection.label)
                        .font(SpatialFont.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("\(Int(detection.confidence * 100))%")
                    .font(SpatialFont.dataSmall)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(6)
        }
        .frame(width: max(rect.width, 48), height: max(rect.height, 48))
        .position(x: rect.midX, y: rect.midY)
    }

    private var borderColor: Color {
        detection.maskAvailable ? .spatialCyan : .warningAmber
    }
}
