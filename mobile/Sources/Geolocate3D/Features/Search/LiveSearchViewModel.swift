import Foundation
import Observation
import RealityKit
import ARKit
import simd
import SwiftData
import SwiftUI
import UIKit

struct ActiveObservation: Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let worldTransform: simd_float4x4
    var lastSeen: Date

    var position: SIMD3<Float> {
        SIMD3(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
    }
}

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

struct RouteGuidanceTarget {
    let objectID: String?
    let label: String
    let worldTransform: simd_float4x4?
}

@Observable
@MainActor
final class LiveSearchViewModel {
    var activeObservations: [ActiveObservation] = []
    var screenProjectedObservations: [ScreenObservation] = []
    var currentResult: SearchResult?
    var currentQuery: String = ""
    var isSearching = false
    var routeWaypoints: [RouteWaypointOverlay] = []
    var routeStatusText: String?

    private let intentParser = IntentParser()
    private let searchPlanner = SearchPlanner()

    @ObservationIgnored private var entityMap = Dictionary<UUID, AnchorEntity>()
    @ObservationIgnored private var routeRootAnchor: AnchorEntity?
    @ObservationIgnored private var routeVersion = 0
    @ObservationIgnored private var renderedRouteVersion = -1
    @ObservationIgnored private var currentCameraTransform: simd_float4x4?
    @ObservationIgnored private var routeTarget: RouteGuidanceTarget?
    @ObservationIgnored private var routeRequestTask: Task<Void, Never>?
    @ObservationIgnored private var lastRouteRequestDate: Date?
    @ObservationIgnored private var lastRoutedCameraTransform: simd_float4x4?

    private let rerouteInterval: TimeInterval = 0.9
    private let rerouteTranslationThreshold: Float = 0.18

    func syncOverlays(in arView: ARView?) {
        guard let arView else { return }

        let activeIDs = Set(activeObservations.map(\.id))

        for (id, entity) in entityMap where !activeIDs.contains(id) {
            arView.scene.removeAnchor(entity)
            entityMap.removeValue(forKey: id)
        }

        for observation in activeObservations {
            if let existing = entityMap[observation.id] {
                existing.transform = Transform(matrix: observation.worldTransform)
            } else {
                let anchor = AnchorEntity(world: observation.worldTransform)
                anchor.name = observation.id.uuidString

                let marker = ModelEntity(
                    mesh: .generateSphere(radius: 0.015),
                    materials: [SimpleMaterial(color: .cyan, isMetallic: true)]
                )
                anchor.addChild(marker)
                arView.scene.addAnchor(anchor)
                entityMap[observation.id] = anchor
            }
        }

        syncRouteOverlay(in: arView)
    }

    func updateScreenProjections(arView: ARView) {
        screenProjectedObservations = activeObservations.compactMap { observation in
            guard let screenPoint = arView.project(observation.position) else { return nil }

            let bounds = arView.bounds
            guard bounds.contains(CGPoint(x: CGFloat(screenPoint.x), y: CGFloat(screenPoint.y))) else {
                return nil
            }

            let confidenceClass: DetectionConfidenceClass
            if observation.confidence >= 0.8 {
                confidenceClass = .confirmedHigh
            } else if observation.confidence >= 0.5 {
                confidenceClass = .confirmedMedium
            } else {
                confidenceClass = .lastSeen
            }

            return ScreenObservation(
                id: observation.id,
                label: observation.label,
                confidence: observation.confidence,
                screenX: CGFloat(screenPoint.x),
                screenY: CGFloat(screenPoint.y),
                confidenceClass: confidenceClass
            )
        }
    }

    func clearOverlays(in arView: ARView?) {
        if let arView {
            for (_, entity) in entityMap {
                arView.scene.removeAnchor(entity)
            }
            if let routeRootAnchor {
                arView.scene.removeAnchor(routeRootAnchor)
            }
        }

        entityMap.removeAll()
        routeRootAnchor = nil
        activeObservations.removeAll()
        screenProjectedObservations.removeAll()
        routeWaypoints.removeAll()
        routeStatusText = nil
        currentCameraTransform = nil
        routeTarget = nil
        routeRequestTask?.cancel()
        routeRequestTask = nil
        lastRouteRequestDate = nil
        lastRoutedCameraTransform = nil
        routeVersion = 0
        renderedRouteVersion = -1
    }

    func updateCameraTransform(_ transform: simd_float4x4) {
        currentCameraTransform = transform
    }

    func setInitialRouteTarget(_ target: LiveRouteTarget?) {
        guard let target else { return }
        let worldTransform = target.worldTransform16.flatMap(simd_float4x4.fromArray)
        routeTarget = RouteGuidanceTarget(
            objectID: target.objectID,
            label: target.label,
            worldTransform: worldTransform
        )
        if let worldTransform {
            activeObservations = [
                ActiveObservation(
                    id: UUID(),
                    label: target.label,
                    confidence: 1.0,
                    worldTransform: worldTransform,
                    lastSeen: Date()
                )
            ]
        }
        currentResult = SearchResult(
            id: UUID(),
            query: "locate \(target.label)",
            resultType: .confirmedHigh,
            label: target.label,
            confidence: 1.0,
            explanation: "Selected object ready for AR guidance.",
            evidence: ["semantic-room-twin"],
            timestamp: Date()
        )
        routeStatusText = "Move the phone slightly so guidance can lock onto \(target.label)."
    }

    func handleCameraTransformUpdate(
        _ transform: simd_float4x4,
        roomID: UUID?,
        backendClient: BackendClient
    ) {
        currentCameraTransform = transform
        guard let roomID, routeTarget != nil else { return }
        requestGuidanceIfNeeded(roomID: roomID, backendClient: backendClient, force: routeWaypoints.isEmpty)
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
        let bestObservation = activeObservations.first
        routeTarget = RouteGuidanceTarget(
            objectID: nil,
            label: bestObservation?.label ?? execution.result.label,
            worldTransform: bestObservation?.worldTransform
        )

        await updateRoute(
            for: execution,
            roomID: roomID,
            backendClient: backendClient
        )

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

    private func updateRoute(
        for execution: SearchExecutionResult,
        roomID: UUID?,
        backendClient: BackendClient
    ) async {
        clearRoute(status: nil)

        guard let roomID else { return }
        guard execution.result.resultType != .noResult else { return }
        guard let startTransform = currentCameraTransform else {
            routeStatusText = "Found a result. Move the phone a bit more so guidance can lock in."
            return
        }
        lastRoutedCameraTransform = startTransform
        lastRouteRequestDate = Date()
        await requestRoute(
            roomID: roomID,
            startTransform: startTransform,
            backendClient: backendClient
        )
    }

    private func clearRoute(status: String?) {
        routeWaypoints.removeAll()
        routeStatusText = status
        routeVersion += 1
    }

    private func requestGuidanceIfNeeded(
        roomID: UUID,
        backendClient: BackendClient,
        force: Bool = false
    ) {
        guard let startTransform = currentCameraTransform else { return }
        guard routeRequestTask == nil else { return }

        if !force {
            if let lastRouteRequestDate, Date().timeIntervalSince(lastRouteRequestDate) < rerouteInterval {
                return
            }
            if let lastRoutedCameraTransform,
               translationDistance(from: lastRoutedCameraTransform, to: startTransform) < rerouteTranslationThreshold,
               !routeWaypoints.isEmpty {
                return
            }
        }

        routeRequestTask = Task { [weak self] in
            guard let self else { return }
            self.lastRoutedCameraTransform = startTransform
            self.lastRouteRequestDate = Date()
            await self.requestRoute(
                roomID: roomID,
                startTransform: startTransform,
                backendClient: backendClient
            )
            self.routeRequestTask = nil
        }
    }

    private func requestRoute(
        roomID: UUID,
        startTransform: simd_float4x4,
        backendClient: BackendClient
    ) async {
        guard let routeTarget else { return }

        do {
            let route = try await backendClient.route(
                roomID: roomID,
                startWorldTransform: startTransform,
                targetObjectID: routeTarget.objectID,
                targetWorldTransform: routeTarget.worldTransform,
                targetLabel: routeTarget.label.isEmpty ? nil : routeTarget.label
            )

            guard route.reachable else {
                routeStatusText = "Guidance unavailable: \(route.reason)."
                return
            }

            let waypoints = route.waypoints.enumerated().compactMap { index, waypoint -> RouteWaypointOverlay? in
                guard let matrix = simd_float4x4.fromArray(waypoint.worldTransform) else {
                    return nil
                }
                return RouteWaypointOverlay(
                    id: waypoint.id,
                    index: index,
                    worldTransform: matrix
                )
            }

            guard !waypoints.isEmpty else {
                routeStatusText = "Guidance came back empty."
                return
            }

            routeWaypoints = waypoints
            routeVersion += 1

            let label = route.targetLabel ?? routeTarget.label
            let count = waypoints.count
            let markerWord = count == 1 ? "marker" : "markers"
            let remainingDistance = routeDistanceMeters(for: waypoints)
            if remainingDistance <= 0.45 {
                routeStatusText = label.isEmpty
                    ? "You’re at the target."
                    : "\(label) should be right here."
            } else {
                routeStatusText = label.isEmpty
                    ? String(format: "Guidance ready. %.1f m remaining.", remainingDistance)
                    : String(format: "Guidance to %@ ready. %.1f m remaining.", label, remainingDistance)
                if count > 1 {
                    routeStatusText?.append(" \(count) \(markerWord).")
                }
            }
        } catch {
            routeStatusText = "Guidance failed: \(error.localizedDescription)"
        }
    }

    private func routeDistanceMeters(for waypoints: [RouteWaypointOverlay]) -> Float {
        guard waypoints.count >= 2 else { return 0 }
        return zip(waypoints, waypoints.dropFirst()).reduce(0) { partial, pair in
            partial + simd_distance(pair.0.position, pair.1.position)
        }
    }

    private func translationDistance(from lhs: simd_float4x4, to rhs: simd_float4x4) -> Float {
        simd_distance(
            SIMD3(lhs.columns.3.x, lhs.columns.3.y, lhs.columns.3.z),
            SIMD3(rhs.columns.3.x, rhs.columns.3.y, rhs.columns.3.z)
        )
    }

    private func syncRouteOverlay(in arView: ARView) {
        if routeWaypoints.isEmpty {
            if let routeRootAnchor {
                arView.scene.removeAnchor(routeRootAnchor)
                self.routeRootAnchor = nil
            }
            renderedRouteVersion = routeVersion
            return
        }

        guard renderedRouteVersion != routeVersion else { return }

        if let routeRootAnchor {
            arView.scene.removeAnchor(routeRootAnchor)
        }

        let routeRoot = AnchorEntity(world: matrix_identity_float4x4)
        let routeColor = UIColor(Color.spatialCyan)
        let goalColor = UIColor(Color.warningAmber)

        for pair in zip(routeWaypoints, routeWaypoints.dropFirst()) {
            if let segment = makeRouteSegment(from: pair.0.position, to: pair.1.position, color: routeColor) {
                routeRoot.addChild(segment)
            }
        }

        for waypoint in routeWaypoints {
            let isStart = waypoint.index == 0
            let isGoal = waypoint.index == routeWaypoints.count - 1
            let radius: Float = isGoal ? 0.030 : (isStart ? 0.022 : 0.016)
            let color = isGoal ? goalColor : (isStart ? .white : routeColor)

            let marker = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [SimpleMaterial(color: color, isMetallic: true)]
            )
            marker.position = waypoint.position
            routeRoot.addChild(marker)
        }

        arView.scene.addAnchor(routeRoot)
        routeRootAnchor = routeRoot
        renderedRouteVersion = routeVersion
    }

    private func makeRouteSegment(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor) -> ModelEntity? {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.001 else { return nil }

        let segment = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.012, 0.012, length)),
            materials: [SimpleMaterial(color: color.withAlphaComponent(0.8), isMetallic: false)]
        )
        segment.position = (start + end) * 0.5
        segment.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(delta))
        return segment
    }
}
