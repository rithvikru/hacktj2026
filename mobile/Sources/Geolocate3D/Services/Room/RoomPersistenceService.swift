import Foundation
import UIKit

struct RoomPersistenceService {
    private let fileManager = FileManager.default

    private var roomsBaseDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("rooms")
    }

    func createRoomDirectory(roomID: UUID) throws -> URL {
        let roomDir = roomsBaseDirectory.appendingPathComponent(roomID.uuidString)
        try fileManager.createDirectory(at: roomDir, withIntermediateDirectories: true)
        return roomDir
    }

    func roomDirectory(for roomID: UUID) -> URL {
        roomsBaseDirectory.appendingPathComponent(roomID.uuidString)
    }

    func usdzURL(for roomID: UUID) -> URL {
        roomDirectory(for: roomID).appendingPathComponent("room.usdz")
    }

    func worldMapURL(for roomID: UUID) -> URL {
        roomDirectory(for: roomID).appendingPathComponent("worldmap.arworldmap")
    }

    func frameBundlesBaseDirectory(for roomID: UUID) -> URL {
        roomDirectory(for: roomID).appendingPathComponent("frame-bundles")
    }

    func frameBundleDirectory(for roomID: UUID, sessionID: UUID) -> URL {
        frameBundlesBaseDirectory(for: roomID).appendingPathComponent(sessionID.uuidString)
    }

    @discardableResult
    func createFrameBundleDirectory(roomID: UUID, sessionID: UUID) throws -> URL {
        let bundleDirectory = frameBundleDirectory(for: roomID, sessionID: sessionID)
        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: bundleDirectory.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: bundleDirectory.appendingPathComponent("depth"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: bundleDirectory.appendingPathComponent("confidence"),
            withIntermediateDirectories: true
        )
        return bundleDirectory
    }

    func frameBundleManifestURL(for roomID: UUID, sessionID: UUID) -> URL {
        frameBundleDirectory(for: roomID, sessionID: sessionID).appendingPathComponent("manifest.json")
    }

    func frameImageURL(roomID: UUID, sessionID: UUID, frameID: UUID) -> URL {
        frameBundleDirectory(for: roomID, sessionID: sessionID)
            .appendingPathComponent("images")
            .appendingPathComponent("\(frameID.uuidString).jpg")
    }

    func frameDepthURL(roomID: UUID, sessionID: UUID, frameID: UUID) -> URL {
        frameBundleDirectory(for: roomID, sessionID: sessionID)
            .appendingPathComponent("depth")
            .appendingPathComponent("\(frameID.uuidString).png")
    }

    func frameConfidenceURL(roomID: UUID, sessionID: UUID, frameID: UUID) -> URL {
        frameBundleDirectory(for: roomID, sessionID: sessionID)
            .appendingPathComponent("confidence")
            .appendingPathComponent("\(frameID.uuidString).png")
    }

    @discardableResult
    func savePreviewImage(_ image: UIImage, roomID: UUID) throws -> String {
        let url = roomDirectory(for: roomID).appendingPathComponent("preview.jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw PersistenceError.imageEncodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    func deleteRoomAssets(roomID: UUID) throws {
        let dir = roomDirectory(for: roomID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    func usdzExists(for roomID: UUID) -> Bool {
        fileManager.fileExists(atPath: usdzURL(for: roomID).path)
    }

    func worldMapExists(for roomID: UUID) -> Bool {
        fileManager.fileExists(atPath: worldMapURL(for: roomID).path)
    }

    enum PersistenceError: LocalizedError {
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed: return "Failed to encode preview image to JPEG."
            }
        }
    }
}
