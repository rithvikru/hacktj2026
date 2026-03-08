import Observation
import Foundation

@Observable
@MainActor
final class HiddenSearchViewModel {
    let roomID: UUID
    var hypotheses: [ObjectHypothesis] = []
    var isLoading: Bool = false

    init(roomID: UUID) {
        self.roomID = roomID
    }

    func loadHypotheses(roomStore: RoomStore) {
        isLoading = true
        if let room = try? roomStore.fetchRoom(id: roomID) {
            hypotheses = room.hypotheses.sorted { $0.rank < $1.rank }
        } else {
            hypotheses = []
        }
        isLoading = false
    }

    func runInference(query: String, roomStore: RoomStore) async {
        isLoading = true
        let executor = HiddenInferenceExecutor(roomID: roomID)

        let room = try? roomStore.fetchRoom(id: roomID)
        let observations = room?.observations ?? []
        let sceneNodes = room?.sceneNodes.filter { $0.roomID == roomID } ?? []
        let results = executor.infer(query: query, observations: observations, sceneNodes: sceneNodes)

        for result in results {
            let hypothesis = ObjectHypothesis(
                queryLabel: result.label,
                type: result.type,
                rank: result.rank,
                confidence: result.confidence,
                reasons: result.reasons
            )
            hypothesis.room = room
            room?.hypotheses.append(hypothesis)
        }

        loadHypotheses(roomStore: roomStore)
        isLoading = false
    }
}
