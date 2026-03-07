import Foundation
import UIKit

/// Manages room asset directories and files in the app's Documents folder.
/// Directory structure: Documents/rooms/{uuid}/room.usdz, worldmap.arworldmap, frames.json, preview.jpg
struct RoomPersistenceService {
    private let fileManager = FileManager.default

    private var roomsBaseDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("rooms")
    }

    /// Creates the room directory and returns its URL.
    func createRoomDirectory(roomID: UUID) throws -> URL {
        let roomDir = roomsBaseDirectory.appendingPathComponent(roomID.uuidString)
        try fileManager.createDirectory(at: roomDir, withIntermediateDirectories: true)
        return roomDir
    }

    /// Returns the directory URL for an existing room.
    func roomDirectory(for roomID: UUID) -> URL {
        roomsBaseDirectory.appendingPathComponent(roomID.uuidString)
    }

    /// Returns the USDZ file URL for a room.
    func usdzURL(for roomID: UUID) -> URL {
        roomDirectory(for: roomID).appendingPathComponent("room.usdz")
    }

    /// Returns the world map archive URL for a room.
    func worldMapURL(for roomID: UUID) -> URL {
        roomDirectory(for: roomID).appendingPathComponent("worldmap.arworldmap")
    }

    /// Saves a preview image (JPEG, 80% quality) and returns the file path.
    @discardableResult
    func savePreviewImage(_ image: UIImage, roomID: UUID) throws -> String {
        let url = roomDirectory(for: roomID).appendingPathComponent("preview.jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw PersistenceError.imageEncodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    /// Deletes the entire room directory and all its contents.
    func deleteRoomAssets(roomID: UUID) throws {
        let dir = roomDirectory(for: roomID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// Checks whether a USDZ file exists for the room.
    func usdzExists(for roomID: UUID) -> Bool {
        fileManager.fileExists(atPath: usdzURL(for: roomID).path)
    }

    /// Checks whether a world map archive exists for the room.
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
