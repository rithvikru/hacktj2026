import Foundation
import simd

/// Rule-based inference engine that generates probable hidden-object locations
/// based on scene graph structure, observation history, and object priors.
struct HiddenInferenceExecutor {
    let roomID: UUID

    struct InferenceResult {
        let label: String
        let type: HypothesisType
        let rank: Int
        let confidence: Double
        let reasons: [String]
        let worldTransform: simd_float4x4
    }

    /// Infer likely locations for a queried object based on available data.
    func infer(query: String, observations: [ObjectObservation],
               sceneNodes: [SceneNode]) -> [InferenceResult] {
        var results: [InferenceResult] = []
        let queryLower = query.lowercased()

        // Rule 1: Check if the object was last seen somewhere
        let matchingObs = observations.filter { $0.label.lowercased().contains(queryLower) }
        if let lastSeen = matchingObs.sorted(by: { $0.observedAt > $1.observedAt }).first {
            results.append(InferenceResult(
                label: "\(lastSeen.label) - Last seen location",
                type: .tagged,
                rank: results.count + 1,
                confidence: 0.7,
                reasons: [
                    "Object was last observed here at \(lastSeen.observedAt.formatted(date: .abbreviated, time: .shortened))",
                    "Confidence: \(Int(lastSeen.confidence * 100))% at last detection"
                ],
                worldTransform: lastSeen.worldTransform
            ))
        }

        // Rule 2: Infer from support surfaces (containers, surfaces, furniture)
        let containers = sceneNodes.filter {
            $0.nodeType == .container || $0.nodeType == .furniture || $0.nodeType == .surface
        }
        for container in containers.prefix(3) {
            let score = surfaceLikelihood(container: container, query: queryLower)
            if score > 0.1 {
                results.append(InferenceResult(
                    label: "\(container.label) area",
                    type: .inferred,
                    rank: results.count + 1,
                    confidence: score,
                    reasons: [
                        "Objects like \"\(query)\" are commonly found on/in \(container.label)",
                        "Scene graph contains this as a \(container.nodeType.rawValue)"
                    ],
                    worldTransform: raisedSurfaceTransform(for: container)
                ))
            }
        }

        // Rule 3: If no observations or scene nodes match, provide generic hypotheses
        if results.isEmpty {
            results.append(InferenceResult(
                label: "Room center area",
                type: .inferred,
                rank: 1,
                confidence: 0.15,
                reasons: [
                    "No prior observations of \"\(query)\" in this room",
                    "Generic estimate based on room layout"
                ],
                worldTransform: inferredRoomCenterTransform(observations: observations, sceneNodes: sceneNodes)
            ))
        }

        // Sort by confidence descending and re-rank
        results.sort { $0.confidence > $1.confidence }
        return results.enumerated().map { index, result in
            InferenceResult(
                label: result.label,
                type: result.type,
                rank: index + 1,
                confidence: result.confidence,
                reasons: result.reasons,
                worldTransform: result.worldTransform
            )
        }
    }

    /// Heuristic score for how likely an object is to be on/in a given container.
    private func surfaceLikelihood(container: SceneNode, query: String) -> Double {
        let label = container.label.lowercased()

        // Common object-surface associations
        let surfaceScores: [String: [String: Double]] = [
            "keys": ["table": 0.5, "desk": 0.5, "counter": 0.4, "shelf": 0.3, "drawer": 0.4],
            "phone": ["table": 0.5, "desk": 0.5, "couch": 0.4, "bed": 0.35, "counter": 0.3],
            "wallet": ["table": 0.4, "desk": 0.4, "counter": 0.3, "drawer": 0.35],
            "remote": ["couch": 0.5, "table": 0.45, "shelf": 0.3, "bed": 0.25],
            "glasses": ["table": 0.4, "desk": 0.45, "nightstand": 0.4, "counter": 0.3],
        ]

        if let objectScores = surfaceScores[query] {
            for (surface, score) in objectScores {
                if label.contains(surface) { return score }
            }
        }

        // Generic fallback: containers and surfaces get a small base score
        switch container.nodeType {
        case .container: return 0.2
        case .surface: return 0.15
        case .furniture: return 0.12
        default: return 0.0
        }
    }

    private func raisedSurfaceTransform(for container: SceneNode) -> simd_float4x4 {
        let baseTransform = simd_float4x4.fromData(container.worldTransform16) ?? matrix_identity_float4x4
        var adjusted = baseTransform
        let yOffset = max(container.extentXYZ.dropFirst().first ?? 0, 0.05) * 0.5 + 0.08
        adjusted.columns.3.y += yOffset
        return adjusted
    }

    private func inferredRoomCenterTransform(
        observations: [ObjectObservation],
        sceneNodes: [SceneNode]
    ) -> simd_float4x4 {
        let nodePositions = sceneNodes.compactMap { node -> SIMD3<Float>? in
            guard let transform = simd_float4x4.fromData(node.worldTransform16) else { return nil }
            return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        let observationPositions = observations.map {
            SIMD3($0.worldTransform.columns.3.x, $0.worldTransform.columns.3.y, $0.worldTransform.columns.3.z)
        }
        let samples = nodePositions + observationPositions
        guard !samples.isEmpty else { return matrix_identity_float4x4 }

        let total = samples.reduce(SIMD3<Float>(repeating: 0)) { partial, sample in
            partial + sample
        }
        let center = total / Float(samples.count)
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(center.x, center.y, center.z, 1)
        return transform
    }
}
