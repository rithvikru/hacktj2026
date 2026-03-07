import SwiftData
import Foundation

@Observable
@MainActor
final class HiddenSearchViewModel {
    let roomID: UUID
    var hypotheses: [ObjectHypothesis] = []
    var isLoading: Bool = false
    var lastQuery: String = ""

    init(roomID: UUID) {
        self.roomID = roomID
    }

    func loadHypotheses(modelContext: ModelContext) {
        isLoading = true
        let descriptor = FetchDescriptor<ObjectHypothesis>(
            predicate: #Predicate { $0.room?.id == roomID },
            sortBy: [SortDescriptor(\.rank)]
        )
        hypotheses = (try? modelContext.fetch(descriptor)) ?? []
        isLoading = false
    }

    /// Run the hidden inference engine for a query and persist results.
    func runInference(query: String, modelContext: ModelContext) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isLoading = true
        lastQuery = trimmedQuery
        let executor = HiddenInferenceExecutor(roomID: roomID)

        let observations = fetchObservations(modelContext: modelContext)
        let sceneNodes = fetchSceneNodes(modelContext: modelContext)
        let results = executor.infer(query: trimmedQuery, observations: observations, sceneNodes: sceneNodes)
        let existingDescriptor = FetchDescriptor<ObjectHypothesis>(
            predicate: #Predicate { $0.room?.id == roomID }
        )
        let existingHypotheses = (try? modelContext.fetch(existingDescriptor)) ?? []
        for hypothesis in existingHypotheses {
            modelContext.delete(hypothesis)
        }

        let room = try? modelContext.fetch(
            FetchDescriptor<RoomRecord>(predicate: #Predicate { $0.id == roomID })
        ).first

        for result in results {
            let hypothesis = ObjectHypothesis(
                queryLabel: trimmedQuery,
                type: result.type,
                rank: result.rank,
                confidence: result.confidence,
                reasons: result.reasons,
                transform: result.worldTransform
            )
            if let room {
                hypothesis.room = room
            }
            modelContext.insert(hypothesis)
        }
        try? modelContext.save()

        loadHypotheses(modelContext: modelContext)
        isLoading = false
    }

    private func fetchObservations(modelContext: ModelContext) -> [ObjectObservation] {
        let descriptor = FetchDescriptor<ObjectObservation>(
            predicate: #Predicate { $0.room?.id == roomID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchSceneNodes(modelContext: ModelContext) -> [SceneNode] {
        let descriptor = FetchDescriptor<SceneNode>(
            predicate: #Predicate { $0.roomID == roomID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
