import Foundation

/// HTTP client for the FastAPI backend.
/// Handles room uploads, reconstruction polling, open-vocabulary search, and query execution.
@Observable
@MainActor
final class BackendClient {
    var baseURL: URL
    var isConnected: Bool = false

    private let session: URLSession
    private let decoder = JSONDecoder()

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
        request.httpBody = try JSONEncoder().encode(OpenVocabSearchRequest(queryText: query))

        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(OpenVocabSearchResponse.self, from: data)
        return response.candidates.enumerated().map { index, candidate in
            BackendSearchResult(
                id: UUID(),
                label: response.queryText,
                confidence: candidate.score,
                worldTransform: candidate.worldTransform,
                evidence: candidate.maskRef == nil ? ["backend-open-vocab"] : ["backend-open-vocab", "mask"],
                explanation: "Candidate \(index + 1) for \"\(response.queryText)\" from saved room frames."
            )
        }
    }

    func queryRoom(roomID: UUID, query: String) async throws -> BackendQueryResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(QueryRequest(queryText: query))

        let (data, _) = try await session.data(for: request)
        return try decoder.decode(BackendQueryResponse.self, from: data)
    }

    // MARK: - Connection Check

    func checkConnection() async {
        do {
            let url = baseURL.appendingPathComponent("healthz")
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

    private enum CodingKeys: String, CodingKey {
        case roomID
        case room_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let roomID = try container.decodeIfPresent(UUID.self, forKey: .roomID) {
            self.roomID = roomID
        } else if let roomID = try container.decodeIfPresent(UUID.self, forKey: .room_id) {
            self.roomID = roomID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.roomID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing room ID.")
            )
        }
    }
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

    init(id: UUID, label: String, confidence: Double, worldTransform: [Float]?, evidence: [String], explanation: String) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.worldTransform = worldTransform
        self.evidence = evidence
        self.explanation = explanation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case confidence
        case score
        case worldTransform
        case world_transform
        case worldTransform16
        case world_transform16
        case evidence
        case explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "result"
        confidence =
            try container.decodeIfPresent(Double.self, forKey: .confidence) ??
            (try container.decodeIfPresent(Double.self, forKey: .score)) ??
            0
        worldTransform =
            try container.decodeIfPresent([Float].self, forKey: .worldTransform) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform)) ??
            (try container.decodeIfPresent([Float].self, forKey: .worldTransform16)) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform16))
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    }
}

struct BackendQueryResponse: Decodable {
    let resultType: String
    let results: [BackendSearchResult]
    let explanation: String

    private enum CodingKeys: String, CodingKey {
        case resultType
        case result_type
        case results
        case explanation
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decodeIfPresent(String.self, forKey: .status)
        resultType =
            try container.decodeIfPresent(String.self, forKey: .resultType) ??
            (try container.decodeIfPresent(String.self, forKey: .result_type)) ??
            status ??
            "no_result"
        results = try container.decodeIfPresent([BackendSearchResult].self, forKey: .results) ?? []
        explanation =
            try container.decodeIfPresent(String.self, forKey: .explanation) ??
            (status == "accepted" ? "Backend accepted the query for processing." : "")
    }
}

private struct QueryRequest: Encodable {
    let queryText: String

    private enum CodingKeys: String, CodingKey {
        case queryText = "query_text"
    }
}

private struct OpenVocabSearchRequest: Encodable {
    let queryText: String
    let frameRefs: [String] = []

    private enum CodingKeys: String, CodingKey {
        case queryText = "query_text"
        case frameRefs = "frame_refs"
    }
}

private struct OpenVocabSearchResponse: Decodable {
    let queryText: String
    let candidates: [OpenVocabCandidate]

    private enum CodingKeys: String, CodingKey {
        case queryText
        case query_text
        case candidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queryText =
            try container.decodeIfPresent(String.self, forKey: .queryText) ??
            (try container.decodeIfPresent(String.self, forKey: .query_text)) ??
            ""
        candidates = try container.decodeIfPresent([OpenVocabCandidate].self, forKey: .candidates) ?? []
    }
}

private struct OpenVocabCandidate: Decodable {
    let score: Double
    let maskRef: String?
    let worldTransform: [Float]?

    private enum CodingKeys: String, CodingKey {
        case score
        case maskRef
        case mask_ref
        case worldTransform
        case world_transform
        case worldTransform16
        case world_transform16
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0
        maskRef =
            try container.decodeIfPresent(String.self, forKey: .maskRef) ??
            (try container.decodeIfPresent(String.self, forKey: .mask_ref))
        worldTransform =
            try container.decodeIfPresent([Float].self, forKey: .worldTransform) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform)) ??
            (try container.decodeIfPresent([Float].self, forKey: .worldTransform16)) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform16))
    }
}
