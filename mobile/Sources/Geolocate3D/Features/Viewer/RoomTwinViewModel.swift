import SwiftData
import Foundation

enum ViewerMode: String, CaseIterable, Sendable {
    case semantic = "Semantic"
    case dense = "Dense"
    case architecture = "Structure"
}

@Observable
@MainActor
final class RoomTwinViewModel {
    let roomID: UUID
    var roomName: String = "Room"
    var observations: [ObjectObservation] = []
    var hypotheses: [ObjectHypothesis] = []
    var reconstructionStatus: ReconstructionStatus = .pending
    var denseAssetURL: URL?
    var denseAssetRemoteURL: URL?
    var denseAssetKind: String?
    var denseRenderer: String?
    var densePhotorealReady: Bool = false
    var statusMessage: String?

    // Layer toggles (legacy — mapped from viewerMode)
    var showScaffold: Bool = true
    var showObjects: Bool = true
    var showHeatmap: Bool = false
    var showDense: Bool = false

    // Semantic scene state
    var semanticScene: SemanticSceneResponse?
    var semanticObjects: [SemanticSceneObject] = []
    var semanticMeshLocalURLs: [String: URL] = [:]
    var selectedSemanticObjectID: String?
    var showSemanticObjects: Bool = true
    var showDensePoints: Bool = false
    var showArchitectureShell: Bool = true
    var viewerMode: ViewerMode = .semantic

    // Secondary toggle chips
    var showLabels: Bool = false
    var showSearchHits: Bool = false
    var showHypothesesOverlay: Bool = false

    private let persistence = RoomPersistenceService()

    init(roomID: UUID) {
        self.roomID = roomID
    }

    var usdzURL: URL {
        persistence.usdzURL(for: roomID)
    }

    var shouldUsePhotorealDenseViewer: Bool {
        densePhotorealReady && denseAssetRemoteURL != nil
    }

    var selectedSemanticObject: SemanticSceneObject? {
        guard let selectedID = selectedSemanticObjectID else { return nil }
        return semanticObjects.first { $0.id == selectedID }
    }

    func selectSemanticObject(id: String) {
        selectedSemanticObjectID = id
    }

    func deselectSemanticObject() {
        selectedSemanticObjectID = nil
    }

    func applyViewerMode(_ mode: ViewerMode) {
        viewerMode = mode
        switch mode {
        case .semantic:
            showSemanticObjects = true
            showDensePoints = false
            showArchitectureShell = true
            showScaffold = true
            showDense = false
            showObjects = true
        case .dense:
            showSemanticObjects = true
            showDensePoints = false
            showArchitectureShell = true
            showScaffold = true
            showDense = false
            showObjects = false
        case .architecture:
            showSemanticObjects = false
            showDensePoints = false
            showArchitectureShell = true
            showScaffold = true
            showDense = false
            showObjects = true
        }
    }

    func loadSemanticScene(roomID: UUID, backendClient: BackendClient) async {
        statusMessage = "Building semantic objects"
        do {
            let response = try await backendClient.fetchSemanticScene(roomID: roomID)
            semanticScene = response
            semanticObjects = response.objects

            let cacheDir = persistence.reconstructionDirectory(for: roomID)
                .appendingPathComponent("semantic_meshes")

            for obj in response.objects {
                guard let meshURL = obj.meshAssetURL else { continue }
                do {
                    let localURL = try await backendClient.downloadSemanticObjectMesh(
                        from: meshURL,
                        suggestedFileName: "\(obj.id).obj",
                        into: cacheDir
                    )
                    semanticMeshLocalURLs[obj.id] = localURL
                } catch {
                    // Mesh download failed; will use fallback box
                }
            }

            if !semanticObjects.isEmpty {
                statusMessage = "Semantic room preview ready"
            } else {
                statusMessage = nil
            }
        } catch {
            // Semantic scene not available — not a failure
            statusMessage = nil
        }
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
        statusMessage = "Preparing room geometry"

        if let localAssetURL = resolveLocalAssetURL(from: room.denseAssetPath) {
            denseAssetURL = localAssetURL
        }

        // Always sync reconstruction state on load.
        await refreshDenseAsset(room: room, modelContext: modelContext, backendClient: backendClient)

        // Load semantic scene
        await loadSemanticScene(roomID: roomID, backendClient: backendClient)
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

            denseAssetKind = assets.denseAssetKind
            denseRenderer = assets.denseRenderer
            densePhotorealReady = assets.densePhotorealReady
            if let remoteAssetPath = assets.denseAssetURL {
                denseAssetRemoteURL = try? backendClient.absoluteAssetURL(for: remoteAssetPath)
            }

            let assetPath = preferredDenseAssetPath(from: assets, fallback: room.denseAssetPath)
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

            if denseAssetURL != nil {
                statusMessage = densePhotorealReady ? "Photoreal room twin ready" : "Dense room preview ready"
            }
        } catch {
            // Dense unavailable is fine if semantic objects exist
            if !semanticObjects.isEmpty {
                statusMessage = "Semantic room preview ready"
            } else {
                statusMessage = "Dense reconstruction unavailable: \(error.localizedDescription)"
            }
        }
    }

    private func preferredDenseAssetPath(
        from assets: ReconstructionAssetsResponse,
        fallback: String?
    ) -> String? {
        if assets.densePhotorealReady, let denseAssetURL = assets.denseAssetURL {
            let pathExtension = URL(fileURLWithPath: denseAssetURL).pathExtension.lowercased()
            if pathExtension == "splat" || assets.pointCloudURL == nil {
                return denseAssetURL
            }
        }

        return assets.denseAssetURL ?? assets.pointCloudURL ?? fallback
    }

    private func resolveLocalAssetURL(from path: String?) -> URL? {
        guard let path else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
