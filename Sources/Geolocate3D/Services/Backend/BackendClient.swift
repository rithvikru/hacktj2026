import Foundation

/// HTTP client for the FastAPI backend.
/// Handles room uploads, reconstruction polling, open-vocabulary search, and query execution.
@Observable
@MainActor
final class BackendClient {
    var baseURL: URL
    var isConnected: Bool = false

    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Room Operations

    func createRoom(name: String, metadata: [String: String] = [:]) async throws -> UUID {
        let url = baseURL.appendingPathComponent("rooms")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["name": name, "metadata": metadata]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CreateRoomResponse.self, from: data)
        return response.roomID
    }

    func uploadFrameBundle(roomID: UUID, bundleURL: URL) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/frame-bundles")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, _) = try await session.upload(for: request, fromFile: bundleURL)
    }

    func triggerReconstruction(roomID: UUID) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/reconstruct")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, _) = try await session.data(for: request)
    }

    func pollReconstructionStatus(roomID: UUID) async throws -> ReconstructionStatus {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/assets")
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ReconstructionStatusResponse.self, from: data)
        return ReconstructionStatus(rawValue: response.status) ?? .pending
    }

    // MARK: - Search Operations

    func openVocabSearch(roomID: UUID, query: String) async throws -> [BackendSearchResult] {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/open-vocab-search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([BackendSearchResult].self, from: data)
    }

    func queryRoom(roomID: UUID, query: String) async throws -> BackendQueryResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(BackendQueryResponse.self, from: data)
    }

    // MARK: - Connection Check

    func checkConnection() async {
        do {
            let url = baseURL.appendingPathComponent("rooms")
            let (_, response) = try await session.data(from: url)
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isConnected = false
        }
    }
}

// MARK: - Response Types

private struct CreateRoomResponse: Decodable {
    let roomID: UUID
}

private struct ReconstructionStatusResponse: Decodable {
    let status: String
}

struct BackendSearchResult: Decodable, Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let worldTransform: [Float]?
    let evidence: [String]
    let explanation: String
}

struct BackendQueryResponse: Decodable {
    let resultType: String
    let results: [BackendSearchResult]
    let explanation: String
}
