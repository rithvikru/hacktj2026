import ARKit
import Foundation

enum WorldMapStore {

    static func save(_ worldMap: ARWorldMap, to url: URL) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )
        try data.write(to: url, options: [.atomic])
    }

    static func load(from url: URL) throws -> ARWorldMap {
        let data = try Data(contentsOf: url)
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw WorldMapStoreError.decodingFailed
        }
        return worldMap
    }

    static func getCurrentWorldMap(from session: ARSession) async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map { continuation.resume(returning: map) }
                else { continuation.resume(throwing: error ?? WorldMapStoreError.unavailable) }
            }
        }
    }

    enum WorldMapStoreError: LocalizedError {
        case decodingFailed
        case unavailable

        var errorDescription: String? {
            switch self {
            case .decodingFailed: return "Failed to decode ARWorldMap from archive."
            case .unavailable: return "World map is not available."
            }
        }
    }
}
