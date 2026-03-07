import Foundation
import RoomPlan
import SwiftData
import simd

/// Manages the RoomPlan capture session lifecycle.
/// Fix 2 applied: no JSONEncoder().encode(room) — CapturedRoom is not Codable.
/// Uses USDZ export only + RoomPersistenceService for asset storage.
@Observable
@MainActor
final class ScanViewModel: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var scanState: ScanState = .initializing
    var detectedObjectCount: Int = 0
    var savedRoomID: UUID?

    private var captureView: RoomCaptureView?
    private var capturedRoomData: CapturedRoomData?
    private var collectedFrames: [FrameRecord] = []

    func startSession(captureView: RoomCaptureView) {
        self.captureView = captureView
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        scanState = .scanning
    }

    func stopSession() {
        captureView?.captureSession.stop()
    }

    // MARK: - RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                     didUpdate room: CapturedRoom) {
        Task { @MainActor in
            detectedObjectCount = room.objects.count + room.doors.count +
                                  room.windows.count + room.openings.count
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                     didEndWith data: CapturedRoomData,
                                     error: Error?) {
        Task { @MainActor in
            capturedRoomData = data
            scanState = .processing
        }
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                  error: Error?) -> Bool {
        true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom,
                                  error: Error?) {
        Task { @MainActor in
            scanState = .ready
        }
    }

    // MARK: - Finalize

    func finalizeScan(modelContext: ModelContext) async {
        guard let data = capturedRoomData else { return }
        scanState = .saving

        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let room = try await builder.capturedRoom(from: data)

            let persistence = RoomPersistenceService()
            let roomID = UUID()
            let roomDir = try persistence.createRoomDirectory(roomID: roomID)
            let roomRecord = RoomRecord(id: roomID, name: defaultRoomName())

            // Export USDZ (Fix 2: no JSONEncoder — CapturedRoom is not Codable)
            let usdzURL = roomDir.appendingPathComponent("room.usdz")
            try room.export(to: usdzURL, exportOptions: .mesh)
            roomRecord.roomUSDZPath = usdzURL.path

            // Save world map if available
            if let arSession = captureView?.captureSession.arSession {
                let worldMap = try? await WorldMapStore.getCurrentWorldMap(from: arSession)
                if let worldMap {
                    let mapURL = roomDir.appendingPathComponent("worldmap.arworldmap")
                    try WorldMapStore.save(worldMap, to: mapURL)
                    roomRecord.worldMapData = try? Data(contentsOf: mapURL)
                }
            }

            // Save frame bundle metadata
            if !collectedFrames.isEmpty {
                let framesURL = roomDir.appendingPathComponent("frames.json")
                let framesData = try JSONEncoder().encode(collectedFrames)
                try framesData.write(to: framesURL)
                roomRecord.frameBundlePath = framesURL.path
            }

            modelContext.insert(roomRecord)
            persistCapturedRoom(room, roomID: roomID, roomRecord: roomRecord, modelContext: modelContext)
            roomRecord.reconstructionStatus = .complete
            roomRecord.updatedAt = Date()
            try modelContext.save()

            savedRoomID = roomID
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }

    // MARK: - Frame Collection

    func collectFrame(_ frame: FrameRecord) {
        collectedFrames.append(frame)
    }

    private func defaultRoomName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Scanned Room \(formatter.string(from: Date()))"
    }

    private func persistCapturedRoom(
        _ room: CapturedRoom,
        roomID: UUID,
        roomRecord: RoomRecord,
        modelContext: ModelContext
    ) {
        for object in room.objects {
            let label = String(describing: object.category)
            let observation = ObjectObservation(
                label: label,
                source: .manual,
                confidence: 0.95,
                transform: object.transform
            )
            observation.room = roomRecord
            observation.visibilityStateRaw = VisibilityState.visible.rawValue
            modelContext.insert(observation)

            let node = SceneNode(
                roomID: roomID,
                nodeType: nodeType(for: label),
                label: label,
                worldTransform: object.transform.toData(),
                extentXYZ: [object.dimensions.x, object.dimensions.y, object.dimensions.z],
                attributesJSON: #"{"source":"roomplan"}"#
            )
            node.room = roomRecord
            modelContext.insert(node)
        }

        for opening in room.openings {
            insertSceneNode(
                label: "opening",
                nodeType: .surface,
                transform: opening.transform,
                dimensions: opening.dimensions,
                roomID: roomID,
                roomRecord: roomRecord,
                modelContext: modelContext
            )
        }

        for door in room.doors {
            insertSceneNode(
                label: "door",
                nodeType: .surface,
                transform: door.transform,
                dimensions: door.dimensions,
                roomID: roomID,
                roomRecord: roomRecord,
                modelContext: modelContext
            )
        }

        for window in room.windows {
            insertSceneNode(
                label: "window",
                nodeType: .surface,
                transform: window.transform,
                dimensions: window.dimensions,
                roomID: roomID,
                roomRecord: roomRecord,
                modelContext: modelContext
            )
        }
    }

    private func insertSceneNode(
        label: String,
        nodeType: SceneNodeType,
        transform: simd_float4x4,
        dimensions: SIMD3<Float>,
        roomID: UUID,
        roomRecord: RoomRecord,
        modelContext: ModelContext
    ) {
        let node = SceneNode(
            roomID: roomID,
            nodeType: nodeType,
            label: label,
            worldTransform: transform.toData(),
            extentXYZ: [dimensions.x, dimensions.y, dimensions.z],
            attributesJSON: #"{"source":"roomplan"}"#
        )
        node.room = roomRecord
        modelContext.insert(node)
    }

    private func nodeType(for label: String) -> SceneNodeType {
        let normalized = label.lowercased()
        if normalized.contains("cabinet") || normalized.contains("drawer") || normalized.contains("storage") {
            return .container
        }
        if normalized.contains("table") || normalized.contains("desk") || normalized.contains("counter") || normalized.contains("shelf") {
            return .surface
        }
        return .furniture
    }
}
