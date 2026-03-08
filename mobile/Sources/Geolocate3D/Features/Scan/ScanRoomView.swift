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
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    ScanStatusPill(state: viewModel.scanState)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                HStack {
                    VStack(alignment: .leading) {
                        Text("\(viewModel.detectedObjectCount)")
                            .font(SpatialFont.dataLarge)
                            .foregroundStyle(.spatialCyan)
                        Text("room features")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                    if !viewModel.liveSpotlightDetections.isEmpty {
                        VStack(alignment: .leading) {
                            Text("\(viewModel.liveSpotlightDetections.count)")
                                .font(SpatialFont.dataLarge)
                                .foregroundStyle(.warningAmber)
                            Text("AI spotlights")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                        }
                    }
                    Spacer()
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
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(detection.maskAvailable ? .spatialCyan : .warningAmber, lineWidth: 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((detection.maskAvailable ? Color.spatialCyan : .warningAmber).opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(detection.maskAvailable ? .spatialCyan : .warningAmber)
                        .frame(width: 8, height: 8)
                    Text(detection.label)
                        .font(SpatialFont.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("\(Int(detection.confidence * 100))%")
                    .font(SpatialFont.dataSmall)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(8)
        }
        .frame(width: max(rect.width, 56), height: max(rect.height, 56))
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: (detection.maskAvailable ? Color.spatialCyan : .warningAmber).opacity(0.25), radius: 18)
    }
}
