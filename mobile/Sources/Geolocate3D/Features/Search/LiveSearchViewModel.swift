import Foundation
import Observation
import RealityKit
import ARKit
import simd
import SwiftData

/// In-memory observation for the active AR session (Fix 6: NOT SwiftData).
struct ActiveObservation: Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let worldTransform: simd_float4x4
    var lastSeen: Date

    var position: SIMD3<Float> {
        SIMD3(worldTransform.columns.3.x,
               worldTransform.columns.3.y,
               worldTransform.columns.3.z)
    }
}

/// Screen-projected observation for SwiftUI overlay positioning.
struct ScreenObservation: Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let screenX: CGFloat
    let screenY: CGFloat
    let confidenceClass: DetectionConfidenceClass
}

struct RouteWaypointOverlay: Identifiable {
    let id: UUID
    let index: Int
    let worldTransform: simd_float4x4

    var position: SIMD3<Float> {
        SIMD3(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
    }
}

@Observable
@MainActor
final class LiveSearchViewModel {
    var activeObservations: [ActiveObservation] = []
    var screenProjectedObservations: [ScreenObservation] = []
    var isSearching = false
    var currentQuery: String = ""
    var currentResult: SearchResult?
    var routeWaypoints: [RouteWaypointOverlay] = []
    var routeStatusText: String?

    private let intentParser = IntentParser()
    private let searchPlanner = SearchPlanner()

    // Entity tracking — maps observation ID to the RealityKit anchor entity
    @ObservationIgnored private var entityMap = Dictionary<UUID, AnchorEntity>()
    @ObservationIgnored private var routeEntityMap = Dictionary<UUID, AnchorEntity>()
    @ObservationIgnored private var currentCameraTransform: simd_float4x4?

    /// Sync 3D pin entities into the ARView scene for each active observation.
    func syncOverlays(in arView: ARView?) {
        guard let arView else { return }

        let activeIDs = Set(activeObservations.map(\.id))
        let routeIDs = Set(routeWaypoints.map(\.id))

        // Remove stale entities
        for (id, entity) in entityMap where !activeIDs.contains(id) {
            arView.scene.removeAnchor(entity)
            entityMap.removeValue(forKey: id)
        }
        for (id, entity) in routeEntityMap where !routeIDs.contains(id) {
            arView.scene.removeAnchor(entity)
            routeEntityMap.removeValue(forKey: id)
        }

        // Add or update entities
        for obs in activeObservations {
            if let existing = entityMap[obs.id] {
                existing.transform = Transform(matrix: obs.worldTransform)
            } else {
                let anchor = AnchorEntity(world: obs.worldTransform)
                anchor.name = obs.id.uuidString

                let sphere = ModelEntity(
                    mesh: .generateSphere(radius: 0.015),
                    materials: [SimpleMaterial(color: .cyan, isMetallic: true)]
                )
                anchor.addChild(sphere)
                arView.scene.addAnchor(anchor)
                entityMap[obs.id] = anchor
            }
        }

        for waypoint in routeWaypoints {
            if let existing = routeEntityMap[waypoint.id] {
                existing.transform = Transform(matrix: waypoint.worldTransform)
                continue
            }

            let anchor = AnchorEntity()
            anchor.transform = Transform(matrix: waypoint.worldTransform)
            anchor.name = waypoint.id.uuidString

            let marker = ModelEntity(
                mesh: .generateBox(size: 0.03),
                materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
            )
            anchor.addChild(marker)
            arView.scene.addAnchor(anchor)
            routeEntityMap[waypoint.id] = anchor
        }
    }

    /// Project 3D world positions to 2D screen coordinates for SwiftUI overlay.
    func updateScreenProjections(arView: ARView) {
        screenProjectedObservations = activeObservations.compactMap { obs in
            guard let screenPoint = arView.project(obs.position) else { return nil }

            // Only include if on-screen
            let bounds = arView.bounds
            guard bounds.contains(CGPoint(x: CGFloat(screenPoint.x), y: CGFloat(screenPoint.y))) else {
                return nil
            }

            let confClass: DetectionConfidenceClass
            if obs.confidence >= 0.8 {
                confClass = .confirmedHigh
            } else if obs.confidence >= 0.5 {
                confClass = .confirmedMedium
            } else {
                confClass = .lastSeen
            }

            return ScreenObservation(
                id: obs.id,
                label: obs.label,
                confidence: obs.confidence,
                screenX: CGFloat(screenPoint.x),
                screenY: CGFloat(screenPoint.y),
                confidenceClass: confClass
            )
        }
    }

    /// Clear all overlays from the scene.
    func clearOverlays(in arView: ARView?) {
        if let arView {
            for (_, entity) in entityMap {
                arView.scene.removeAnchor(entity)
            }
            for (_, entity) in routeEntityMap {
                arView.scene.removeAnchor(entity)
            }
        }
        entityMap.removeAll()
        routeEntityMap.removeAll()
        activeObservations.removeAll()
        screenProjectedObservations.removeAll()
        routeWaypoints.removeAll()
        routeStatusText = nil
        currentCameraTransform = nil
    }

    func updateCameraTransform(_ transform: simd_float4x4) {
        currentCameraTransform = transform
    }

    func executeSearch(
        query: String,
        roomID: UUID?,
        modelContext: ModelContext,
        backendClient: BackendClient
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        currentQuery = trimmedQuery
        isSearching = true
        let intent = intentParser.parse(trimmedQuery, roomID: roomID)
        let execution = await searchPlanner.execute(
            intent: intent,
            roomID: roomID,
            modelContext: modelContext,
            backendClient: backendClient
        )
        currentResult = execution.result
        activeObservations = makeActiveObservations(
            from: execution.localObservations,
            backendResults: execution.backendResults
        )
        await refreshRoute(roomID: roomID, backendClient: backendClient)
        isSearching = false
    }

    private func makeActiveObservations(
        from observations: [ObjectObservation],
        backendResults: [BackendSearchResult]
    ) -> [ActiveObservation] {
        var active = observations.map { observation in
            ActiveObservation(
                id: observation.id,
                label: observation.label,
                confidence: observation.confidence,
                worldTransform: observation.worldTransform,
                lastSeen: observation.observedAt
            )
        }

        let backendObservations = backendResults.compactMap { result -> ActiveObservation? in
            guard let values = result.worldTransform, let matrix = simd_float4x4.fromArray(values) else {
                return nil
            }
            return ActiveObservation(
                id: result.id,
                label: result.label,
                confidence: result.confidence,
                worldTransform: matrix,
                lastSeen: Date()
            )
        }
        active.append(contentsOf: backendObservations)
        return active.sorted { $0.confidence > $1.confidence }
    }

    private func refreshRoute(roomID: UUID?, backendClient: BackendClient) async {
        routeWaypoints.removeAll()
        routeStatusText = nil

        guard let roomID else { return }
        guard let startTransform = currentCameraTransform else {
            routeStatusText = "Move the phone to establish route guidance."
            return
        }
        guard let target = activeObservations.first else { return }

        do {
            let response = try await backendClient.route(
                roomID: roomID,
                startWorldTransform: startTransform,
                targetWorldTransform: target.worldTransform,
                targetLabel: target.label
            )

            if response.reachable {
                routeWaypoints = response.waypoints.enumerated().compactMap { index, waypoint in
                    guard let transform = simd_float4x4.fromArray(waypoint.worldTransform) else { return nil }
                    return RouteWaypointOverlay(
                        id: waypoint.id,
                        index: index + 1,
                        worldTransform: transform
                    )
                }
                routeStatusText = routeWaypoints.isEmpty
                    ? "Target located. Walk directly toward the marker."
                    : "Route ready with \(routeWaypoints.count) waypoint\(routeWaypoints.count == 1 ? "" : "s")."
            } else {
                routeStatusText = response.reason.capitalized
            }
        } catch {
            routeStatusText = "Route unavailable: \(error.localizedDescription)"
        }
    }
}
