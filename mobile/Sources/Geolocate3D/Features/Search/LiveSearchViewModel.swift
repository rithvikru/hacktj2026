import Foundation
import RealityKit
import ARKit
import simd

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

struct ScreenObservation: Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let screenX: CGFloat
    let screenY: CGFloat
    let confidenceClass: DetectionConfidenceClass
}

@Observable
@MainActor
final class LiveSearchViewModel {
    var activeObservations: [ActiveObservation] = []
    var screenProjectedObservations: [ScreenObservation] = []
    var isSearching = false
    var currentQuery: String = ""

    private var entityMap: [UUID: AnchorEntity] = []

    func syncOverlays(in arView: ARView?) {
        guard let arView else { return }

        let activeIDs = Set(activeObservations.map(\.id))

        for (id, entity) in entityMap where !activeIDs.contains(id) {
            arView.scene.removeAnchor(entity)
            entityMap.removeValue(forKey: id)
        }

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
    }

    func updateScreenProjections(arView: ARView) {
        screenProjectedObservations = activeObservations.compactMap { obs in
            guard let screenPoint = arView.project(obs.position) else { return nil }

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

    func clearOverlays(in arView: ARView?) {
        if let arView {
            for (_, entity) in entityMap {
                arView.scene.removeAnchor(entity)
            }
        }
        entityMap.removeAll()
        activeObservations.removeAll()
        screenProjectedObservations.removeAll()
    }

    func executeSearch(query: String) async {
        currentQuery = query
        isSearching = true

        isSearching = false
    }
}
