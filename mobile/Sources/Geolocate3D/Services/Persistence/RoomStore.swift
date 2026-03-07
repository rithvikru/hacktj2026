import SwiftData
import Foundation
import simd

@Observable
@MainActor
final class RoomStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllRooms() throws -> [RoomRecord] {
        let descriptor = FetchDescriptor<RoomRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRoom(id: UUID) throws -> RoomRecord? {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func createRoom(name: String) throws -> RoomRecord {
        let room = RoomRecord(name: name)
        modelContext.insert(room)
        try modelContext.save()
        return room
    }

    func deleteRoom(_ room: RoomRecord) throws {
        modelContext.delete(room)
        try modelContext.save()
    }

    func saveObservation(label: String, source: ObservationSource,
                         confidence: Double, transform: simd_float4x4,
                         roomID: UUID) throws {
        guard let room = try fetchRoom(id: roomID) else { return }
        let observation = ObjectObservation(
            label: label, source: source,
            confidence: confidence, transform: transform
        )
        observation.room = room
        modelContext.insert(observation)
        room.updatedAt = Date()
        try modelContext.save()
    }

    func fetchObservations(roomID: UUID) throws -> [ObjectObservation] {
        let descriptor = FetchDescriptor<ObjectObservation>(
            predicate: #Predicate { $0.room?.id == roomID },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
