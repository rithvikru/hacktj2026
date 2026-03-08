import Foundation
import UIKit

struct PersistedWearableFrame {
    let imagePath: String
    let imageBase64: String
}

struct PersistedWearableSessionSummary: Codable {
    let sessionID: String
    let homeID: String
    let deviceName: String
    let createdAt: Date
    var updatedAt: Date
    var localFrameCount: Int
    var backendFrameCount: Int
    var lastFrameID: String?
    var lastFrameTimestamp: Date?
    let sessionDirectoryPath: String
}

struct WearablePersistenceService {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var wearablesBaseDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("wearables")
    }

    func createSessionDirectory(sessionID: String) throws -> URL {
        let directory = wearablesBaseDirectory.appendingPathComponent(sessionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("frames"),
            withIntermediateDirectories: true
        )
        return directory
    }

    func sessionDirectoryURL(sessionID: String) -> URL {
        wearablesBaseDirectory.appendingPathComponent(sessionID)
    }

    func sessionSummaryURL(sessionID: String) -> URL {
        sessionDirectoryURL(sessionID: sessionID).appendingPathComponent("session.json")
    }

    func frameImageURL(sessionID: String, frameID: UUID) -> URL {
        wearablesBaseDirectory
            .appendingPathComponent(sessionID)
            .appendingPathComponent("frames")
            .appendingPathComponent("\(frameID.uuidString).jpg")
    }

    func initializeSessionSummary(sessionID: String, homeID: String, deviceName: String) throws -> PersistedWearableSessionSummary {
        let directory = try createSessionDirectory(sessionID: sessionID)
        let summary = PersistedWearableSessionSummary(
            sessionID: sessionID,
            homeID: homeID,
            deviceName: deviceName,
            createdAt: Date(),
            updatedAt: Date(),
            localFrameCount: 0,
            backendFrameCount: 0,
            lastFrameID: nil,
            lastFrameTimestamp: nil,
            sessionDirectoryPath: directory.path
        )
        try saveSessionSummary(summary)
        return summary
    }

    func saveFrameImage(_ image: UIImage, sessionID: String, frameID: UUID) throws -> PersistedWearableFrame {
        try createSessionDirectory(sessionID: sessionID)
        let url = frameImageURL(sessionID: sessionID, frameID: frameID)
        guard let data = image.jpegData(compressionQuality: 0.72) else {
            throw PersistenceError.imageEncodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return PersistedWearableFrame(
            imagePath: url.path,
            imageBase64: data.base64EncodedString()
        )
    }

    func loadSessionSummary(sessionID: String) throws -> PersistedWearableSessionSummary {
        let data = try Data(contentsOf: sessionSummaryURL(sessionID: sessionID))
        return try decoder.decode(PersistedWearableSessionSummary.self, from: data)
    }

    func saveSessionSummary(_ summary: PersistedWearableSessionSummary) throws {
        try createSessionDirectory(sessionID: summary.sessionID)
        let data = try encoder.encode(summary)
        try data.write(to: sessionSummaryURL(sessionID: summary.sessionID), options: [.atomic])
    }

    func recordFrame(
        sessionID: String,
        frameID: UUID,
        timestamp: Date,
        backendFrameCount: Int? = nil
    ) throws -> PersistedWearableSessionSummary {
        var summary = try loadSessionSummary(sessionID: sessionID)
        summary.updatedAt = Date()
        summary.localFrameCount += 1
        summary.lastFrameID = frameID.uuidString
        summary.lastFrameTimestamp = timestamp
        if let backendFrameCount {
            summary.backendFrameCount = backendFrameCount
        }
        try saveSessionSummary(summary)
        return summary
    }

    func syncBackendFrameCount(sessionID: String, backendFrameCount: Int) throws -> PersistedWearableSessionSummary {
        var summary = try loadSessionSummary(sessionID: sessionID)
        summary.updatedAt = Date()
        summary.backendFrameCount = backendFrameCount
        try saveSessionSummary(summary)
        return summary
    }

    enum PersistenceError: LocalizedError {
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return "Failed to encode wearable frame to JPEG."
            }
        }
    }
}
