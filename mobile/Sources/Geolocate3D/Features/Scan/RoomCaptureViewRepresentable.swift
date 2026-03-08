import SwiftUI
import RoomPlan

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let viewModel: ScanViewModel
    let backendClient: BackendClient?

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = viewModel
        captureView.delegate = viewModel
        viewModel.startSession(captureView: captureView, backendClient: backendClient)
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
