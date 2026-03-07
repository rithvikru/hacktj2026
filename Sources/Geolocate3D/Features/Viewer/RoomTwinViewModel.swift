import SwiftData
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

    func loadRoom(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == roomID }
        )
        descriptor.fetchLimit = 1
        if let room = try? modelContext.fetch(descriptor).first {
            roomName = room.name
            observations = room.observations
        }
    }
}
