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
