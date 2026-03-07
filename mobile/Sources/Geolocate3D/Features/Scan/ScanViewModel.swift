import Foundation
import ARKit
import RoomPlan
import SwiftData
import simd
import UIKit

@Observable
@MainActor
final class ScanViewModel: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, NSCoding {
    var scanState: ScanState = .initializing
    var detectedObjectCount: Int = 0
    var savedRoomID: UUID?

    override init() { super.init() }
    nonisolated required init?(coder: NSCoder) { nil }
    nonisolated func encode(with coder: NSCoder) {}

    private let persistence = RoomPersistenceService()
    private let frameBundleWriter = FrameBundleWriter()
    private let minimumKeyframeInterval: TimeInterval = 0.75
    private let maximumKeyframeInterval: TimeInterval = 2.0
    private let minimumKeyframeTranslation: Float = 0.12
    private let minimumKeyframeRotation: Float = 0.20

    private var captureView: RoomCaptureView?
    private var capturedRoomData: CapturedRoomData?
    private var activeRoomID: UUID?
    private var activeSessionID: UUID?
    private var activeRoomDirectory: URL?
    private var collectedFrames: [FrameRecord] = []
    private var captureSamplingTask: Task<Void, Never>?
    private var lastCapturedAt: Date?
    private var lastCapturedTransform: simd_float4x4?

    deinit {
        let task = MainActor.assumeIsolated { captureSamplingTask }
        task?.cancel()
    }

    func startSession(captureView: RoomCaptureView) {
        self.captureView = captureView
        resetCaptureState()

        let roomID = UUID()
        let sessionID = UUID()
        activeRoomID = roomID
        activeSessionID = sessionID

        do {
            activeRoomDirectory = try persistence.createRoomDirectory(roomID: roomID)
            try persistence.createFrameBundleDirectory(roomID: roomID, sessionID: sessionID)
        } catch {
            scanState = .error(error.localizedDescription)
            return
        }

        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        startFrameSampling()
        scanState = .scanning
    }

    func stopSession() {
        stopFrameSampling()
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
            captureCurrentFrame(force: true)
            stopFrameSampling()
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

    func finalizeScan(modelContext: ModelContext) async {
        guard let data = capturedRoomData,
              let roomID = activeRoomID,
              let sessionID = activeSessionID,
              let roomDir = activeRoomDirectory else { return }
        scanState = .saving

        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let room = try await builder.capturedRoom(from: data)
            let roomRecord = RoomRecord(id: roomID, name: defaultRoomName())

            let usdzURL = roomDir.appendingPathComponent("room.usdz")
            try room.export(to: usdzURL, exportOptions: .mesh)
            roomRecord.roomUSDZPath = usdzURL.path
            if let previewImagePath,
               let previewImage = UIImage(contentsOfFile: previewImagePath) {
                roomRecord.previewImagePath = try persistence.savePreviewImage(previewImage, roomID: roomID)
            }

            if let arSession = captureView?.captureSession.arSession {
                let worldMap = try? await WorldMapStore.getCurrentWorldMap(from: arSession)
                if let worldMap {
                    let mapURL = roomDir.appendingPathComponent("worldmap.arworldmap")
                    try WorldMapStore.save(worldMap, to: mapURL)
                    roomRecord.worldMapData = try? Data(contentsOf: mapURL)
                }
            }

            let bundleManifest = FrameBundleManifest(
                roomID: roomID,
                sessionID: sessionID,
                frames: collectedFrames,
                auxiliaryAssets: collectedFrames.map { frame in
                    FrameAuxiliaryAssets(
                        frameID: frame.id,
                        confidenceMapPath: frame.confidenceMapPath
                    )
                },
                keyframeSelection: currentKeyframeSelection
            )
            let bundleURL = persistence.frameBundleManifestURL(for: roomID, sessionID: sessionID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let bundleData = try encoder.encode(bundleManifest)
            try bundleData.write(to: bundleURL, options: [.atomic])
            roomRecord.frameBundlePath = bundleURL.path

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

    func collectFrame(_ frame: FrameRecord) {
        collectedFrames.append(frame)
    }

    private var currentKeyframeSelection: KeyframeSelection {
        KeyframeSelection(
            minimumIntervalSeconds: minimumKeyframeInterval,
            maximumIntervalSeconds: maximumKeyframeInterval,
            minimumTranslationMeters: minimumKeyframeTranslation,
            minimumRotationRadians: minimumKeyframeRotation
        )
    }

    private var previewImagePath: String? {
        guard !collectedFrames.isEmpty else { return nil }
        return collectedFrames[collectedFrames.count / 2].imagePath
    }

    private func resetCaptureState() {
        captureSamplingTask?.cancel()
        captureSamplingTask = nil
        capturedRoomData = nil
        activeRoomID = nil
        activeSessionID = nil
        activeRoomDirectory = nil
        collectedFrames.removeAll()
        lastCapturedAt = nil
        lastCapturedTransform = nil
        detectedObjectCount = 0
        savedRoomID = nil
    }

    private func startFrameSampling() {
        captureSamplingTask?.cancel()
        captureSamplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.captureCurrentFrame(force: false)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private func stopFrameSampling() {
        captureSamplingTask?.cancel()
        captureSamplingTask = nil
    }

    private func captureCurrentFrame(force: Bool) {
        guard force || isActivelyScanning else {
            return
        }

        guard let captureView,
              let roomID = activeRoomID,
              let sessionID = activeSessionID,
              let frame = captureView.captureSession.arSession.currentFrame else {
            return
        }

        let capturedAt = Date()
        guard shouldCaptureFrame(frame, capturedAt: capturedAt, force: force) else {
            return
        }

        do {
            let frameID = UUID()
            let assets = try frameBundleWriter.writeFrameAssets(
                frame: frame,
                roomID: roomID,
                sessionID: sessionID,
                frameID: frameID,
                persistence: persistence
            )
            let record = FrameRecord(
                roomID: roomID,
                sessionID: sessionID,
                timestamp: capturedAt,
                imagePath: assets.imagePath,
                depthPath: assets.depthPath,
                confidenceMapPath: assets.confidenceMapPath,
                cameraTransform16: frame.camera.transform.columnMajorArray,
                intrinsics9: frame.camera.intrinsics.columnMajorArray,
                trackingState: trackingStateLabel(for: frame.camera.trackingState)
            )
            collectFrame(record)
            lastCapturedAt = capturedAt
            lastCapturedTransform = frame.camera.transform
        } catch {
            stopFrameSampling()
            scanState = .error(error.localizedDescription)
        }
    }

    private var isActivelyScanning: Bool {
        if case .scanning = scanState {
            return true
        }
        return false
    }

    private func shouldCaptureFrame(_ frame: ARFrame, capturedAt: Date, force: Bool) -> Bool {
        if force {
            return true
        }

        guard case .normal = frame.camera.trackingState else {
            return false
        }

        guard let lastCapturedAt else {
            return true
        }

        let elapsed = capturedAt.timeIntervalSince(lastCapturedAt)
        if elapsed < minimumKeyframeInterval {
            return false
        }
        if elapsed >= maximumKeyframeInterval {
            return true
        }

        guard let lastCapturedTransform else {
            return true
        }

        let translation = translationDistance(
            from: lastCapturedTransform,
            to: frame.camera.transform
        )
        let rotation = angularDistance(
            from: lastCapturedTransform,
            to: frame.camera.transform
        )
        return translation >= minimumKeyframeTranslation || rotation >= minimumKeyframeRotation
    }

    private func translationDistance(from lhs: simd_float4x4, to rhs: simd_float4x4) -> Float {
        let left = SIMD3(lhs.columns.3.x, lhs.columns.3.y, lhs.columns.3.z)
        let right = SIMD3(rhs.columns.3.x, rhs.columns.3.y, rhs.columns.3.z)
        return simd_length(right - left)
    }

    private func angularDistance(from lhs: simd_float4x4, to rhs: simd_float4x4) -> Float {
        let lhsRotation = simd_normalize(simd_quatf(lhs))
        let rhsRotation = simd_normalize(simd_quatf(rhs))
        let dotProduct = min(1.0, max(-1.0, abs(simd_dot(lhsRotation.vector, rhsRotation.vector))))
        return 2 * acos(dotProduct)
    }

    private func trackingStateLabel(for trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .normal:
            return "normal"
        case .notAvailable:
            return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "limited_initializing"
            case .relocalizing:
                return "limited_relocalizing"
            case .excessiveMotion:
                return "limited_excessive_motion"
            case .insufficientFeatures:
                return "limited_insufficient_features"
            @unknown default:
                return "limited_unknown"
            }
        }
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
