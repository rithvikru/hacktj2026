import Observation
import Foundation

@Observable
@MainActor
final class RoomTwinViewModel {
    let roomID: UUID
    var roomName: String = "Room"
    var observations: [ObjectObservation] = []

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

    func loadRoom(roomStore: RoomStore) {
        if let room = try? roomStore.fetchRoom(id: roomID) {
            roomName = room.name
            observations = room.observations
        }
    }
}
