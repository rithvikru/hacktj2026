import Foundation
import UIKit

struct PersistedWearableFrame {
    let imagePath: String
    let imageBase64: String
}

struct WearablePersistenceService {
    private let fileManager = FileManager.default

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

    func frameImageURL(sessionID: String, frameID: UUID) -> URL {
        wearablesBaseDirectory
            .appendingPathComponent(sessionID)
            .appendingPathComponent("frames")
            .appendingPathComponent("\(frameID.uuidString).jpg")
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
