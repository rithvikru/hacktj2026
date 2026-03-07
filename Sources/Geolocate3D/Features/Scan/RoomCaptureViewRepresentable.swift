import SwiftUI
import RoomPlan

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let viewModel: ScanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = viewModel
        captureView.delegate = viewModel
        viewModel.startSession(captureView: captureView)
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
