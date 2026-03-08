import Foundation

struct OutdoorSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var frameCount: Int

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.frameCount = 0
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}
