import SwiftData
import Foundation

@Observable
@MainActor
final class RoomTwinViewModel {
    let roomID: UUID
    var roomName: String = "Room"
    var observations: [ObjectObservation] = []
    var hypotheses: [ObjectHypothesis] = []
    var reconstructionStatus: ReconstructionStatus = .pending
    var denseAssetURL: URL?
    var statusMessage: String?

    // Layer toggles
    var showScaffold: Bool = true
    var showObjects: Bool = true
    var showHeatmap: Bool = false
    var showDense: Bool = false

    private let persistence = RoomPersistenceService()

    init(roomID: UUID) {
        self.roomID = roomID
    }

    var usdzURL: URL {
        persistence.usdzURL(for: roomID)
    }

    func loadRoom(modelContext: ModelContext, backendClient: BackendClient) async {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == roomID }
        )
        descriptor.fetchLimit = 1
        guard let room = try? modelContext.fetch(descriptor).first else { return }

        roomName = room.name
        observations = room.observations
        hypotheses = room.hypotheses.sorted { $0.rank < $1.rank }
        reconstructionStatus = room.reconstructionStatus
        statusMessage = nil

        if let localAssetURL = resolveLocalAssetURL(from: room.denseAssetPath) {
            denseAssetURL = localAssetURL
            return
        }

        if room.reconstructionStatus == .complete || room.denseAssetPath != nil {
            await refreshDenseAsset(room: room, modelContext: modelContext, backendClient: backendClient)
        }
    }

    func refreshAssets(modelContext: ModelContext, backendClient: BackendClient) async {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == roomID }
        )
        descriptor.fetchLimit = 1
        guard let room = try? modelContext.fetch(descriptor).first else { return }
        await refreshDenseAsset(room: room, modelContext: modelContext, backendClient: backendClient)
    }

    private func refreshDenseAsset(
        room: RoomRecord,
        modelContext: ModelContext,
        backendClient: BackendClient
    ) async {
        do {
            let assets = try await backendClient.fetchReconstructionAssets(roomID: roomID)
            if let status = ReconstructionStatus(rawValue: assets.status) {
                reconstructionStatus = status
                room.reconstructionStatus = status
            }

            let assetPath = assets.denseAssetURL ?? assets.pointCloudURL ?? room.denseAssetPath
            guard let assetPath else {
                try? modelContext.save()
                return
            }

            if let localAssetURL = resolveLocalAssetURL(from: assetPath) {
                denseAssetURL = localAssetURL
                room.denseAssetPath = localAssetURL.path
                try? modelContext.save()
                return
            }

            let reconstructionDirectory = try persistence.createReconstructionDirectory(roomID: roomID)
            let fileName = URL(string: assetPath)?.lastPathComponent ?? URL(fileURLWithPath: assetPath).lastPathComponent
            let downloadedURL = try await backendClient.downloadAsset(
                from: assetPath,
                suggestedFileName: fileName,
                into: reconstructionDirectory
            )
            room.denseAssetPath = downloadedURL.path
            denseAssetURL = downloadedURL
            try? modelContext.save()
        } catch {
            statusMessage = "Dense reconstruction unavailable: \(error.localizedDescription)"
        }
    }

    private func resolveLocalAssetURL(from path: String?) -> URL? {
        guard let path else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
