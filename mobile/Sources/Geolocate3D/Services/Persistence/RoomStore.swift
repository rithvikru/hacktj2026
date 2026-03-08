import Observation
import Foundation
import simd

@MainActor
final class RoomStore: Observable {
    private let _$observationRegistrar = ObservationRegistrar()
    private var _rooms: [RoomRecord] = []

    var rooms: [RoomRecord] {
        get {
            _$observationRegistrar.access(self, keyPath: \.rooms)
            return _rooms
        }
        set {
            _$observationRegistrar.withMutation(of: self, keyPath: \.rooms) {
                _rooms = newValue
            }
        }
    }

    init() {}

    func fetchAllRooms() throws -> [RoomRecord] {
        rooms.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchRoom(id: UUID) throws -> RoomRecord? {
        rooms.first { $0.id == id }
    }

    @discardableResult
    func createRoom(name: String) throws -> RoomRecord {
        let room = RoomRecord(name: name)
        rooms.append(room)
        return room
    }

    func deleteRoom(_ room: RoomRecord) throws {
        rooms.removeAll { $0.id == room.id }
    }

    func insertRoom(_ room: RoomRecord) {
        if !rooms.contains(where: { $0.id == room.id }) {
            rooms.append(room)
        }
    }

    func insertObservation(_ observation: ObjectObservation) {}
    func insertNode(_ node: SceneNode) {}
    func insertHypothesis(_ hypothesis: ObjectHypothesis) {}
    func save() throws {}

    func saveObservation(label: String, source: ObservationSource,
                         confidence: Double, transform: simd_float4x4,
                         roomID: UUID) throws {
        guard let room = try fetchRoom(id: roomID) else { return }
        let observation = ObjectObservation(
            label: label, source: source,
            confidence: confidence, transform: transform
        )
        observation.room = room
        room.observations.append(observation)
        room.updatedAt = Date()
    }

    func fetchObservations(roomID: UUID) throws -> [ObjectObservation] {
        guard let room = try fetchRoom(id: roomID) else { return [] }
        return room.observations.sorted { $0.observedAt > $1.observedAt }
    }
}
