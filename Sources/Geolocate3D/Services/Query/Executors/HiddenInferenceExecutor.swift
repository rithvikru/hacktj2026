import Foundation

struct HiddenInferenceExecutor {
    let roomID: UUID

    struct InferenceResult {
        let label: String
        let type: HypothesisType
        let rank: Int
        let confidence: Double
        let reasons: [String]
    }

    func infer(query: String, observations: [ObjectObservation],
               sceneNodes: [SceneNode]) -> [InferenceResult] {
        var results: [InferenceResult] = []
        let queryLower = query.lowercased()

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
                ]
            ))
        }

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
                    ]
                ))
            }
        }

        if results.isEmpty {
            results.append(InferenceResult(
                label: "Room center area",
                type: .inferred,
                rank: 1,
                confidence: 0.15,
                reasons: [
                    "No prior observations of \"\(query)\" in this room",
                    "Generic estimate based on room layout"
                ]
            ))
        }

        results.sort { $0.confidence > $1.confidence }
        return results.enumerated().map { index, result in
            InferenceResult(
                label: result.label,
                type: result.type,
                rank: index + 1,
                confidence: result.confidence,
                reasons: result.reasons
            )
        }
    }

    private func surfaceLikelihood(container: SceneNode, query: String) -> Double {
        let label = container.label.lowercased()

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

        switch container.nodeType {
        case .container: return 0.2
        case .surface: return 0.15
        case .furniture: return 0.12
        default: return 0.0
        }
    }
}
