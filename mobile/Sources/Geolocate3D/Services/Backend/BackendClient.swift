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

    func createRoom(id preferredRoomID: UUID? = nil, name: String, metadata: [String: String] = [:]) async throws -> UUID {
        let url = baseURL.appendingPathComponent("rooms")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["name": name, "metadata": metadata]
        if let preferredRoomID {
            body["roomId"] = preferredRoomID.uuidString
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CreateRoomResponse.self, from: data)
        return response.roomID
    }

    func uploadFrameBundle(roomID: UUID, bundleURL: URL) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/frame-bundles")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try makeFrameBundleMultipartBody(bundleURL: bundleURL, boundary: boundary)
        let (_, _) = try await session.upload(for: request, from: body)
    }

    func triggerReconstruction(roomID: UUID) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/reconstruct")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, _) = try await session.data(for: request)
    }

    func pollReconstructionStatus(roomID: UUID) async throws -> ReconstructionStatus {
        let response = try await fetchReconstructionAssets(roomID: roomID)
        return ReconstructionStatus(rawValue: response.status) ?? .pending
    }

    func fetchReconstructionAssets(roomID: UUID) async throws -> ReconstructionAssetsResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/assets")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(ReconstructionAssetsResponse.self, from: data)
    }

    // MARK: - Search Operations

    func openVocabSearch(roomID: UUID, query: String) async throws -> [BackendSearchResult] {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/open-vocab-search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenVocabSearchRequest(queryText: query))

        let (data, _) = try await session.data(for: request)
        if let response = try? decoder.decode(OpenVocabSearchResponse.self, from: data) {
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
        return try decoder.decode([BackendSearchResult].self, from: data)
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

    private func makeFrameBundleMultipartBody(bundleURL: URL, boundary: String) throws -> Data {
        let fileManager = FileManager.default
        let bundleDirectory = resolvedBundleDirectory(for: bundleURL)
        let manifestURL = bundleDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var body = Data()
        try appendMultipartFile(
            fieldName: "manifest",
            fileURL: manifestURL,
            fileName: "manifest.json",
            mimeType: "application/json",
            boundary: boundary,
            into: &body
        )
        try appendDirectoryFiles(
            fieldName: "images",
            directoryURL: bundleDirectory.appendingPathComponent("images"),
            mimeType: "image/jpeg",
            boundary: boundary,
            into: &body
        )
        try appendDirectoryFiles(
            fieldName: "depth_files",
            directoryURL: bundleDirectory.appendingPathComponent("depth"),
            mimeType: "image/png",
            boundary: boundary,
            into: &body
        )
        try appendDirectoryFiles(
            fieldName: "confidence_files",
            directoryURL: bundleDirectory.appendingPathComponent("confidence"),
            mimeType: "image/png",
            boundary: boundary,
            into: &body
        )
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }

    private func resolvedBundleDirectory(for bundleURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return bundleURL
        }
        return bundleURL.deletingLastPathComponent()
    }

    private func appendDirectoryFiles(
        fieldName: String,
        directoryURL: URL,
        mimeType: String,
        boundary: String,
        into body: inout Data
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for fileURL in files {
            try appendMultipartFile(
                fieldName: fieldName,
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                mimeType: mimeType,
                boundary: boundary,
                into: &body
            )
        }
    }

    private func appendMultipartFile(
        fieldName: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        boundary: String,
        into body: inout Data
    ) throws {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        body.appendUTF8("\r\n")
    }
}

// MARK: - Response Types

private struct CreateRoomResponse: Decodable {
    let roomID: UUID

    private enum CodingKeys: String, CodingKey {
        case roomID
        case roomId
        case room_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let roomID = try container.decodeIfPresent(UUID.self, forKey: .roomID) {
            self.roomID = roomID
        } else if let roomID = try container.decodeIfPresent(UUID.self, forKey: .roomId) {
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

struct ReconstructionAssetsResponse: Decodable {
    let status: String
    let denseAssetURL: String?
    let pointCloudURL: String?
    let frameBundleURL: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case reconstructionStatus
        case reconstruction_status
        case denseAssetURL
        case dense_asset_url
        case splatURL
        case splat_url
        case pointCloudURL
        case point_cloud_url
        case frameBundleURL
        case frame_bundle_url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status =
            try container.decodeIfPresent(String.self, forKey: .status) ??
            (try container.decodeIfPresent(String.self, forKey: .reconstructionStatus)) ??
            (try container.decodeIfPresent(String.self, forKey: .reconstruction_status)) ??
            ReconstructionStatus.pending.rawValue
        denseAssetURL =
            try container.decodeIfPresent(String.self, forKey: .denseAssetURL) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_asset_url)) ??
            (try container.decodeIfPresent(String.self, forKey: .splatURL)) ??
            (try container.decodeIfPresent(String.self, forKey: .splat_url))
        pointCloudURL =
            try container.decodeIfPresent(String.self, forKey: .pointCloudURL) ??
            (try container.decodeIfPresent(String.self, forKey: .point_cloud_url))
        frameBundleURL =
            try container.decodeIfPresent(String.self, forKey: .frameBundleURL) ??
            (try container.decodeIfPresent(String.self, forKey: .frame_bundle_url))
    }
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
        case confidence
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
        score =
            try container.decodeIfPresent(Double.self, forKey: .score) ??
            (try container.decodeIfPresent(Double.self, forKey: .confidence)) ??
            0
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

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
