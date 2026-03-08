import Foundation
import CoreGraphics
import simd

@Observable
@MainActor
final class BackendClient {
    static let defaultBaseURL = URL(string: "http://localhost:8000")!
    private static let storedBaseURLKey = "hacktj2026.backendBaseURL"

    var baseURL: URL
    var isConnected: Bool = false

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? Self.storedBaseURL() ?? Self.defaultBaseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    var baseURLString: String {
        baseURL.absoluteString
    }

    func updateBaseURL(_ urlString: String) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else {
            throw URLError(.badURL)
        }
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.storedBaseURLKey)
    }

    func resetBaseURL() {
        baseURL = Self.defaultBaseURL
        UserDefaults.standard.set(Self.defaultBaseURL.absoluteString, forKey: Self.storedBaseURLKey)
    }
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

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        let decodedResponse = try JSONDecoder().decode(CreateRoomResponse.self, from: data)
        return decodedResponse.roomID
    }

    func uploadFrameBundle(roomID: UUID, bundleURL: URL) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/frame-bundles")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try makeFrameBundleMultipartBody(bundleURL: bundleURL, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)
        try validateHTTPResponse(response, data: data)
    }

    func triggerReconstruction(roomID: UUID) async throws {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/reconstruct")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    func pollReconstructionStatus(roomID: UUID) async throws -> ReconstructionStatus {
        let response = try await fetchReconstructionAssets(roomID: roomID)
        return ReconstructionStatus(rawValue: response.status) ?? .pending
    }

    func fetchReconstructionAssets(roomID: UUID) async throws -> ReconstructionAssetsResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/assets")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(ReconstructionAssetsResponse.self, from: data)
    }

    func openVocabSearch(roomID: UUID, query: String) async throws -> [BackendSearchResult] {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/open-vocab-search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenVocabSearchRequest(queryText: query))

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
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

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try decoder.decode(BackendQueryResponse.self, from: data)
    }

    func chat(roomID: UUID, query: String, messages: [BackendChatMessage] = []) async throws -> BackendChatResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                queryText: query,
                roomID: roomID.uuidString,
                messages: messages
            )
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try decoder.decode(BackendChatResponse.self, from: data)
    }

    func route(
        roomID: UUID,
        startWorldTransform: simd_float4x4,
        targetWorldTransform: simd_float4x4? = nil,
        targetLabel: String? = nil,
        gridResolutionM: Float = 0.20,
        obstacleInflationRadiusM: Float = 0.25
    ) async throws -> BackendRouteResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/route")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RouteRequest(
                startWorldTransform16: startWorldTransform.columnMajorArray,
                targetWorldTransform16: targetWorldTransform?.columnMajorArray,
                targetLabel: targetLabel,
                gridResolutionM: gridResolutionM,
                obstacleInflationRadiusM: obstacleInflationRadiusM
            )
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try decoder.decode(BackendRouteResponse.self, from: data)
    }

    func downloadAsset(from assetPath: String, suggestedFileName: String? = nil, into directory: URL) async throws -> URL {
        let resolvedURL = try resolvedAssetURL(for: assetPath)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = suggestedFileName ?? resolvedURL.lastPathComponent
        let destinationURL = directory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let (data, _) = try await session.data(from: resolvedURL)
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    func absoluteAssetURL(for assetPath: String) throws -> URL {
        try resolvedAssetURL(for: assetPath)
    }

    func checkConnection() async {
        do {
            let url = baseURL.appendingPathComponent("healthz")
            let (_, response) = try await session.data(from: url)
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isConnected = false
        }
    }

    func fetchSemanticScene(roomID: UUID) async throws -> SemanticSceneResponse {
        let url = baseURL.appendingPathComponent("rooms/\(roomID.uuidString)/semantic-objects")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try decoder.decode(SemanticSceneResponse.self, from: data)
    }

    func downloadSemanticObjectMesh(from assetPath: String, suggestedFileName: String?, into directory: URL) async throws -> URL {
        let resolvedURL = try resolvedAssetURL(for: assetPath)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = suggestedFileName ?? resolvedURL.lastPathComponent
        let destinationURL = directory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let (data, _) = try await session.data(from: resolvedURL)
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    func liveScanDetect(imageURL: URL, labels: [String], maxCandidates: Int = 6) async throws -> [LiveScanDetection] {
        let url = baseURL.appendingPathComponent("scan/live-detect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        try appendMultipartFile(
            fieldName: "file",
            fileURL: imageURL,
            fileName: imageURL.lastPathComponent,
            mimeType: "image/jpeg",
            boundary: boundary,
            into: &body
        )
        appendMultipartText(
            fieldName: "labels",
            value: labels.joined(separator: ","),
            boundary: boundary,
            into: &body
        )
        appendMultipartText(
            fieldName: "maxCandidates",
            value: String(maxCandidates),
            boundary: boundary,
            into: &body
        )
        body.appendUTF8("--\(boundary)--\r\n")

        let (data, response) = try await session.upload(for: request, from: body)
        try validateHTTPResponse(response, data: data)
        let decoded = try decoder.decode(LiveScanDetectResponse.self, from: data)
        return decoded.detections
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
        try appendMultipartFiles(
            in: bundleDirectory.appendingPathComponent("images"),
            fieldName: "images",
            mimeType: "image/jpeg",
            boundary: boundary,
            into: &body
        )
        try appendMultipartFiles(
            in: bundleDirectory.appendingPathComponent("depth"),
            fieldName: "depth_files",
            mimeType: "image/png",
            boundary: boundary,
            into: &body
        )
        try appendMultipartFiles(
            in: bundleDirectory.appendingPathComponent("confidence"),
            fieldName: "confidence_files",
            mimeType: "image/png",
            boundary: boundary,
            into: &body
        )
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }

    private func appendMultipartFiles(
        in directory: URL,
        fieldName: String,
        mimeType: String,
        boundary: String,
        into body: inout Data
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for fileURL in fileURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
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

    private func resolvedBundleDirectory(for bundleURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return bundleURL
        }
        return bundleURL.deletingLastPathComponent()
    }

    private func resolvedAssetURL(for assetPath: String) throws -> URL {
        if let directURL = URL(string: assetPath), let scheme = directURL.scheme, !scheme.isEmpty {
            return directURL
        }
        if FileManager.default.fileExists(atPath: assetPath) {
            return URL(fileURLWithPath: assetPath)
        }
        let trimmedPath = assetPath.hasPrefix("/") ? String(assetPath.dropFirst()) : assetPath
        guard !trimmedPath.isEmpty else {
            throw URLError(.badURL)
        }
        return baseURL.appendingPathComponent(trimmedPath)
    }

    private static func storedBaseURL() -> URL? {
        guard let value = UserDefaults.standard.string(forKey: storedBaseURLKey) else { return nil }
        return URL(string: value)
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

    private func appendMultipartText(
        fieldName: String,
        value: String,
        boundary: String,
        into body: inout Data
    ) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n")
        body.appendUTF8(value)
        body.appendUTF8("\r\n")
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw BackendError.httpStatus(code: httpResponse.statusCode, body: body)
        }
    }
}

private enum BackendError: LocalizedError {
    case httpStatus(code: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            if body.isEmpty {
                return "Backend request failed with HTTP \(code)."
            }
            return "Backend request failed with HTTP \(code): \(body)"
        }
    }
}

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
    let denseAssetKind: String?
    let denseRenderer: String?
    let densePhotorealReady: Bool
    let denseDatasetManifestURL: String?
    let denseTransformsURL: String?
    let denseDiagnosticsURL: String?

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
        case denseAssetKind
        case dense_asset_kind
        case denseRenderer
        case dense_renderer
        case densePhotorealReady
        case dense_photoreal_ready
        case denseDatasetManifestURL
        case dense_dataset_manifest_url
        case denseTransformsURL
        case dense_transforms_url
        case denseDiagnosticsURL
        case dense_diagnostics_url
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
        denseAssetKind =
            try container.decodeIfPresent(String.self, forKey: .denseAssetKind) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_asset_kind))
        denseRenderer =
            try container.decodeIfPresent(String.self, forKey: .denseRenderer) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_renderer))
        densePhotorealReady =
            try container.decodeIfPresent(Bool.self, forKey: .densePhotorealReady) ??
            (try container.decodeIfPresent(Bool.self, forKey: .dense_photoreal_ready)) ??
            false
        denseDatasetManifestURL =
            try container.decodeIfPresent(String.self, forKey: .denseDatasetManifestURL) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_dataset_manifest_url))
        denseTransformsURL =
            try container.decodeIfPresent(String.self, forKey: .denseTransformsURL) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_transforms_url))
        denseDiagnosticsURL =
            try container.decodeIfPresent(String.self, forKey: .denseDiagnosticsURL) ??
            (try container.decodeIfPresent(String.self, forKey: .dense_diagnostics_url))
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

struct LiveScanDetection: Decodable, Identifiable {
    let id: UUID
    let label: String
    let confidence: Double
    let bboxXYXYNorm: [CGFloat]
    let maskAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case confidence
        case bboxXYXYNorm
        case bbox_xyxy_norm
        case maskAvailable
        case mask_available
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "object"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        let values =
            try container.decodeIfPresent([Double].self, forKey: .bboxXYXYNorm) ??
            (try container.decodeIfPresent([Double].self, forKey: .bbox_xyxy_norm)) ??
            []
        bboxXYXYNorm = values.map { CGFloat($0) }
        maskAvailable =
            try container.decodeIfPresent(Bool.self, forKey: .maskAvailable) ??
            (try container.decodeIfPresent(Bool.self, forKey: .mask_available)) ??
            false
    }
}

private struct LiveScanDetectResponse: Decodable {
    let detections: [LiveScanDetection]
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

struct BackendChatMessage: Codable, Identifiable {
    enum Role: String, Codable {
        case system, user, assistant, tool
    }

    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

struct BackendChatResponse: Decodable {
    let roomID: UUID?
    let reply: BackendChatMessage
    let plannerSummary: String?
    let provider: String
    let model: String

    private enum CodingKeys: String, CodingKey {
        case roomID
        case roomId
        case room_id
        case reply
        case plannerSummary
        case planner_summary
        case provider
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID =
            try container.decodeIfPresent(UUID.self, forKey: .roomID) ??
            (try container.decodeIfPresent(UUID.self, forKey: .roomId)) ??
            (try container.decodeIfPresent(UUID.self, forKey: .room_id))
        reply = try container.decode(BackendChatMessage.self, forKey: .reply)
        plannerSummary =
            try container.decodeIfPresent(String.self, forKey: .plannerSummary) ??
            (try container.decodeIfPresent(String.self, forKey: .planner_summary))
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "backend"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
    }
}

struct BackendRouteWaypoint: Decodable, Identifiable {
    let id: UUID
    let x: Float
    let y: Float
    let z: Float
    let worldTransform: [Float]

    init(id: UUID = UUID(), x: Float, y: Float, z: Float, worldTransform: [Float]) {
        self.id = id
        self.x = x
        self.y = y
        self.z = z
        self.worldTransform = worldTransform
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case z
        case worldTransform
        case world_transform
        case worldTransform16
        case world_transform16
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        x = try container.decodeIfPresent(Float.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Float.self, forKey: .y) ?? 0
        z = try container.decodeIfPresent(Float.self, forKey: .z) ?? 0
        worldTransform =
            try container.decodeIfPresent([Float].self, forKey: .worldTransform) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform)) ??
            (try container.decodeIfPresent([Float].self, forKey: .worldTransform16)) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform16)) ??
            []
    }
}

struct BackendRouteResponse: Decodable {
    let reachable: Bool
    let reason: String
    let targetLabel: String?
    let snappedGoalWorldTransform: [Float]?
    let waypoints: [BackendRouteWaypoint]

    private enum CodingKeys: String, CodingKey {
        case reachable
        case reason
        case targetLabel
        case target_label
        case snappedGoalWorldTransform
        case snappedGoalWorldTransform16
        case snapped_goal_world_transform16
        case waypoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reachable = try container.decodeIfPresent(Bool.self, forKey: .reachable) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "route unavailable"
        targetLabel =
            try container.decodeIfPresent(String.self, forKey: .targetLabel) ??
            (try container.decodeIfPresent(String.self, forKey: .target_label))
        snappedGoalWorldTransform =
            try container.decodeIfPresent([Float].self, forKey: .snappedGoalWorldTransform) ??
            (try container.decodeIfPresent([Float].self, forKey: .snappedGoalWorldTransform16)) ??
            (try container.decodeIfPresent([Float].self, forKey: .snapped_goal_world_transform16))
        waypoints = try container.decodeIfPresent([BackendRouteWaypoint].self, forKey: .waypoints) ?? []
    }
}

private struct QueryRequest: Encodable {
    let queryText: String
    let sessionMode = "live"
    let frameSelectionMode = "live_priority"

    private enum CodingKeys: String, CodingKey {
        case queryText = "query_text"
        case sessionMode = "session_mode"
        case frameSelectionMode = "frame_selection_mode"
    }
}

private struct ChatRequest: Encodable {
    let queryText: String
    let roomID: String
    let messages: [BackendChatMessage]
    let includePlannerContext = true
    let includeQueryResult = true

    private enum CodingKeys: String, CodingKey {
        case queryText = "query_text"
        case roomID = "room_id"
        case messages
        case includePlannerContext = "include_planner_context"
        case includeQueryResult = "include_query_result"
    }
}

private struct RouteRequest: Encodable {
    let startWorldTransform16: [Float]
    let targetWorldTransform16: [Float]?
    let targetLabel: String?
    let gridResolutionM: Float
    let obstacleInflationRadiusM: Float

    private enum CodingKeys: String, CodingKey {
        case startWorldTransform16 = "start_world_transform16"
        case targetWorldTransform16 = "target_world_transform16"
        case targetLabel = "target_label"
        case gridResolutionM = "grid_resolution_m"
        case obstacleInflationRadiusM = "obstacle_inflation_radius_m"
    }
}

private struct OpenVocabSearchRequest: Encodable {
    let queryText: String
    let frameRefs: [String] = []
    let frameSelectionMode = "live_priority"

    private enum CodingKeys: String, CodingKey {
        case queryText = "query_text"
        case frameRefs = "frame_refs"
        case frameSelectionMode = "frame_selection_mode"
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

// MARK: - Semantic Scene DTOs

struct SupportRelationDTO: Decodable, Sendable {
    let parentID: String?
    let parentLabel: String?
    let relationType: String?

    private enum CodingKeys: String, CodingKey {
        case parentID
        case parent_id
        case parentLabel
        case parent_label
        case relationType
        case relation_type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parentID =
            try container.decodeIfPresent(String.self, forKey: .parentID) ??
            (try container.decodeIfPresent(String.self, forKey: .parent_id))
        parentLabel =
            try container.decodeIfPresent(String.self, forKey: .parentLabel) ??
            (try container.decodeIfPresent(String.self, forKey: .parent_label))
        relationType =
            try container.decodeIfPresent(String.self, forKey: .relationType) ??
            (try container.decodeIfPresent(String.self, forKey: .relation_type))
    }

    var displayDescription: String {
        guard let parentLabel, let relationType else { return "" }
        return "\(relationType) \(parentLabel)"
    }
}

struct SemanticSceneObject: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let confidence: Double
    let worldTransform16: [Float]?
    let centerXYZ: [Float]?
    let extentXYZ: [Float]?
    let baseAnchorXYZ: [Float]?
    let supportAnchorXYZ: [Float]?
    let supportNormalXYZ: [Float]?
    let principalAxisXYZ: [Float]?
    let yawRadians: Float?
    let footprintXYZ: [[Float]]?
    let meshKind: String?
    let meshAssetURL: String?
    let pointCount: Int?
    let supportingViewCount: Int?
    let maskSupportedViews: [String]?
    let bboxFallbackViews: [String]?
    let supportRelation: SupportRelationDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case confidence
        case worldTransform16
        case world_transform16
        case centerXYZ
        case center_xyz
        case extentXYZ
        case extent_xyz
        case baseAnchorXYZ
        case base_anchor_xyz
        case supportAnchorXYZ
        case support_anchor_xyz
        case supportNormalXYZ
        case support_normal_xyz
        case principalAxisXYZ
        case principal_axis_xyz
        case yawRadians
        case yaw_radians
        case footprintXYZ
        case footprint_xyz
        case meshKind
        case mesh_kind
        case meshAssetURL
        case mesh_asset_url
        case pointCount
        case point_count
        case supportingViewCount
        case supporting_view_count
        case maskSupportedViews
        case mask_supported_views
        case bboxFallbackViews
        case bbox_fallback_views
        case supportRelation
        case support_relation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "object"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        worldTransform16 =
            try container.decodeIfPresent([Float].self, forKey: .worldTransform16) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform16))
        centerXYZ =
            try container.decodeIfPresent([Float].self, forKey: .centerXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .center_xyz))
        extentXYZ =
            try container.decodeIfPresent([Float].self, forKey: .extentXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .extent_xyz))
        baseAnchorXYZ =
            try container.decodeIfPresent([Float].self, forKey: .baseAnchorXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .base_anchor_xyz))
        supportAnchorXYZ =
            try container.decodeIfPresent([Float].self, forKey: .supportAnchorXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .support_anchor_xyz))
        supportNormalXYZ =
            try container.decodeIfPresent([Float].self, forKey: .supportNormalXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .support_normal_xyz))
        principalAxisXYZ =
            try container.decodeIfPresent([Float].self, forKey: .principalAxisXYZ) ??
            (try container.decodeIfPresent([Float].self, forKey: .principal_axis_xyz))
        yawRadians =
            try container.decodeIfPresent(Float.self, forKey: .yawRadians) ??
            (try container.decodeIfPresent(Float.self, forKey: .yaw_radians))
        footprintXYZ =
            try container.decodeIfPresent([[Float]].self, forKey: .footprintXYZ) ??
            (try container.decodeIfPresent([[Float]].self, forKey: .footprint_xyz))
        meshKind =
            try container.decodeIfPresent(String.self, forKey: .meshKind) ??
            (try container.decodeIfPresent(String.self, forKey: .mesh_kind))
        meshAssetURL =
            try container.decodeIfPresent(String.self, forKey: .meshAssetURL) ??
            (try container.decodeIfPresent(String.self, forKey: .mesh_asset_url))
        pointCount =
            try container.decodeIfPresent(Int.self, forKey: .pointCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .point_count))
        supportingViewCount =
            try container.decodeIfPresent(Int.self, forKey: .supportingViewCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .supporting_view_count))
        maskSupportedViews =
            try container.decodeIfPresent([String].self, forKey: .maskSupportedViews) ??
            (try container.decodeIfPresent([String].self, forKey: .mask_supported_views))
        bboxFallbackViews =
            try container.decodeIfPresent([String].self, forKey: .bboxFallbackViews) ??
            (try container.decodeIfPresent([String].self, forKey: .bbox_fallback_views))
        supportRelation =
            try container.decodeIfPresent(SupportRelationDTO.self, forKey: .supportRelation) ??
            (try container.decodeIfPresent(SupportRelationDTO.self, forKey: .support_relation))
    }
}

struct SemanticSceneResponse: Decodable, Sendable {
    let objects: [SemanticSceneObject]
    let roomID: String?
    let sceneVersion: String?

    private enum CodingKeys: String, CodingKey {
        case objects
        case semanticObjects
        case semantic_objects
        case roomID
        case room_id
        case sceneVersion
        case scene_version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objects =
            try container.decodeIfPresent([SemanticSceneObject].self, forKey: .objects) ??
            (try container.decodeIfPresent([SemanticSceneObject].self, forKey: .semanticObjects)) ??
            (try container.decodeIfPresent([SemanticSceneObject].self, forKey: .semantic_objects)) ??
            []
        roomID =
            try container.decodeIfPresent(String.self, forKey: .roomID) ??
            (try container.decodeIfPresent(String.self, forKey: .room_id))
        sceneVersion =
            try container.decodeIfPresent(String.self, forKey: .sceneVersion) ??
            (try container.decodeIfPresent(String.self, forKey: .scene_version))
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
