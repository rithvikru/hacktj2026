import Foundation

enum ReconstructionStatus: String, Codable {
    case pending, uploading, processing, complete, failed
}
