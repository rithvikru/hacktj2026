import Foundation

struct FrameRecord: Codable, Identifiable {
    let id: UUID
    let roomID: UUID
    let timestamp: Date
    let imagePath: String
    let depthPath: String?
    let confidenceMapPath: String?
    let cameraTransform16: [Float]
    let intrinsics9: [Float]
    let trackingState: String
    var selectedForUpload: Bool

    init(roomID: UUID, timestamp: Date = Date(), imagePath: String,
         depthPath: String? = nil, confidenceMapPath: String? = nil,
         cameraTransform16: [Float], intrinsics9: [Float],
         trackingState: String, selectedForUpload: Bool = false) {
        self.id = UUID()
        self.roomID = roomID
        self.timestamp = timestamp
        self.imagePath = imagePath
        self.depthPath = depthPath
        self.confidenceMapPath = confidenceMapPath
        self.cameraTransform16 = cameraTransform16
        self.intrinsics9 = intrinsics9
        self.trackingState = trackingState
        self.selectedForUpload = selectedForUpload
    }
}
