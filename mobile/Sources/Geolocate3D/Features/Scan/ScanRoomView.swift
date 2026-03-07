import SwiftUI
import RoomPlan

struct ScanRoomView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var viewModel = ScanViewModel()

    var body: some View {
        ZStack {
            RoomCaptureViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()

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
                        Text("objects detected")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                    Spacer()
                    if viewModel.scanState == .ready {
                        Button("Save Room") {
                            Task { await viewModel.finalizeScan() }
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
