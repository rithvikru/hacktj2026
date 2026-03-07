import Foundation

struct FrameRecord: Codable, Identifiable {
    let id: UUID
    let roomID: UUID
    let sessionID: UUID
    let timestamp: Date
    let imagePath: String
    let depthPath: String?
    let confidenceMapPath: String?
    let cameraTransform16: [Float]
    let intrinsics9: [Float]
    let trackingState: String
    let selectedForTraining: Bool
    let selectedForEval: Bool

    init(id: UUID = UUID(), roomID: UUID, sessionID: UUID, timestamp: Date = Date(), imagePath: String,
         depthPath: String? = nil, confidenceMapPath: String? = nil,
         cameraTransform16: [Float], intrinsics9: [Float],
         trackingState: String, selectedForTraining: Bool = false,
         selectedForEval: Bool = false) {
        self.id = id
        self.roomID = roomID
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.imagePath = imagePath
        self.depthPath = depthPath
        self.confidenceMapPath = confidenceMapPath
        self.cameraTransform16 = cameraTransform16
        self.intrinsics9 = intrinsics9
        self.trackingState = trackingState
        self.selectedForTraining = selectedForTraining
        self.selectedForEval = selectedForEval
    }

    enum CodingKeys: String, CodingKey {
        case id = "frame_id"
        case roomID = "room_id"
        case sessionID = "session_id"
        case timestamp
        case imagePath = "image_path"
        case depthPath = "depth_path"
        case confidenceMapPath = "confidence_map_path"
        case cameraTransform16 = "camera_transform16"
        case intrinsics9 = "intrinsics9"
        case trackingState = "tracking_state"
        case selectedForTraining = "selected_for_training"
        case selectedForEval = "selected_for_eval"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roomID = try container.decode(UUID.self, forKey: .roomID)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        depthPath = try container.decodeIfPresent(String.self, forKey: .depthPath)
        confidenceMapPath = try container.decodeIfPresent(String.self, forKey: .confidenceMapPath)
        cameraTransform16 = try container.decode([Float].self, forKey: .cameraTransform16)
        intrinsics9 = try container.decode([Float].self, forKey: .intrinsics9)
        trackingState = try container.decode(String.self, forKey: .trackingState)
        selectedForTraining = try container.decode(Bool.self, forKey: .selectedForTraining)
        selectedForEval = try container.decode(Bool.self, forKey: .selectedForEval)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encodeIfPresent(depthPath, forKey: .depthPath)
        try container.encodeIfPresent(confidenceMapPath, forKey: .confidenceMapPath)
        try container.encode(cameraTransform16, forKey: .cameraTransform16)
        try container.encode(intrinsics9, forKey: .intrinsics9)
        try container.encode(trackingState, forKey: .trackingState)
        try container.encode(selectedForTraining, forKey: .selectedForTraining)
        try container.encode(selectedForEval, forKey: .selectedForEval)
    }

    func bundleRelative(to bundleDirectory: URL) -> FrameRecord {
        FrameRecord(
            id: id,
            roomID: roomID,
            sessionID: sessionID,
            timestamp: timestamp,
            imagePath: relativePath(for: imagePath, bundleDirectory: bundleDirectory) ?? imagePath,
            depthPath: relativePath(for: depthPath, bundleDirectory: bundleDirectory),
            confidenceMapPath: relativePath(for: confidenceMapPath, bundleDirectory: bundleDirectory),
            cameraTransform16: cameraTransform16,
            intrinsics9: intrinsics9,
            trackingState: trackingState,
            selectedForTraining: selectedForTraining,
            selectedForEval: selectedForEval
        )
    }

    private func relativePath(for path: String?, bundleDirectory: URL) -> String? {
        guard let path else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        let bundlePath = bundleDirectory.standardizedFileURL.path
        let standardizedFilePath = fileURL.standardizedFileURL.path
        if standardizedFilePath.hasPrefix(bundlePath + "/") {
            return String(standardizedFilePath.dropFirst(bundlePath.count + 1))
        }
        if standardizedFilePath.hasPrefix(bundlePath) {
            return String(standardizedFilePath.dropFirst(bundlePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let imagesRange = standardizedFilePath.range(of: "/images/") {
            return "images/" + String(standardizedFilePath[imagesRange.upperBound...])
        }
        if let depthRange = standardizedFilePath.range(of: "/depth/") {
            return "depth/" + String(standardizedFilePath[depthRange.upperBound...])
        }
        if let confidenceRange = standardizedFilePath.range(of: "/confidence/") {
            return "confidence/" + String(standardizedFilePath[confidenceRange.upperBound...])
        }
        return fileURL.lastPathComponent
    }
}
