import Foundation
import RoomPlan
import SwiftData

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

    func finalizeScan() async {
        guard let data = capturedRoomData else { return }
        scanState = .saving

        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let room = try await builder.capturedRoom(from: data)

            let persistence = RoomPersistenceService()
            let roomID = UUID()
            let roomDir = try persistence.createRoomDirectory(roomID: roomID)

            let usdzURL = roomDir.appendingPathComponent("room.usdz")
            try room.export(to: usdzURL, exportOptions: .mesh)

            if let arSession = captureView?.captureSession.arSession {
                let worldMap = try? await WorldMapStore.getCurrentWorldMap(from: arSession)
                if let worldMap {
                    let mapURL = roomDir.appendingPathComponent("worldmap.arworldmap")
                    try WorldMapStore.save(worldMap, to: mapURL)
                }
            }

            if !collectedFrames.isEmpty {
                let framesURL = roomDir.appendingPathComponent("frames.json")
                let framesData = try JSONEncoder().encode(collectedFrames)
                try framesData.write(to: framesURL)
            }

            savedRoomID = roomID
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }

    func collectFrame(_ frame: FrameRecord) {
        collectedFrames.append(frame)
    }
}
