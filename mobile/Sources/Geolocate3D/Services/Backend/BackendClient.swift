import Foundation

@Observable
@MainActor
final class BackendClient {
    static let defaultBaseURLString = "http://localhost:8000"

    var baseURL: URL
    var isConnected: Bool = false

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = URL(string: BackendClient.defaultBaseURLString)!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func createWearableSession(
        homeID: String,
        deviceName: String,
        source: String,
        samplingFPS: Double
    ) async throws -> WearableSessionStatusResponse {
        let url = baseURL.appendingPathComponent("wearables/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "home_id": homeID,
                "device_name": deviceName,
                "source": source,
                "sampling_fps": samplingFPS,
            ]
        )

        let (data, response) = try await session.data(for: request)
        try ensureSuccessfulResponse(response, data: data)
        return try decoder.decode(WearableSessionStatusResponse.self, from: data)
    }

    func uploadWearableFrames(sessionID: String, frames: [WearableFrameUpload]) async throws -> WearableFrameUploadResponse {
        let url = baseURL.appendingPathComponent("wearables/sessions/\(sessionID)/frames")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(WearableFrameBatchRequest(events: frames))
        let (data, response) = try await session.data(for: request)
        try ensureSuccessfulResponse(response, data: data)
        return try decoder.decode(WearableFrameUploadResponse.self, from: data)
    }

    func fetchWearableSession(sessionID: String) async throws -> WearableSessionStatusResponse {
        let url = baseURL.appendingPathComponent("wearables/sessions/\(sessionID)")
        let (data, response) = try await session.data(from: url)
        try ensureSuccessfulResponse(response, data: data)
        return try decoder.decode(WearableSessionStatusResponse.self, from: data)
    }

    func updateWearableSessionStatus(sessionID: String, status: String) async throws -> WearableSessionStatusResponse {
        let url = baseURL.appendingPathComponent("wearables/sessions/\(sessionID)/status")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (data, response) = try await session.data(for: request)
        try ensureSuccessfulResponse(response, data: data)
        return try decoder.decode(WearableSessionStatusResponse.self, from: data)
    }

    func rebuildTopology(homeID: String) async throws -> HomeTopologyResponse {
        let url = baseURL.appendingPathComponent("homes/\(homeID)/topology/rebuild")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, _) = try await session.data(for: request)
        return try decoder.decode(HomeTopologyResponse.self, from: data)
    }

    func fetchTopology(homeID: String) async throws -> HomeTopologyResponse {
        let url = baseURL.appendingPathComponent("homes/\(homeID)/topology")
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(HomeTopologyResponse.self, from: data)
    }

    func createHome(name: String, metadata: [String: String] = [:]) async throws -> String {
        let url = baseURL.appendingPathComponent("homes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["name": name, "metadata": metadata]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(CreateHomeResponse.self, from: data)
        return response.homeID
    }

    func attachRoom(homeID: String, roomID: UUID) async throws {
        let url = baseURL.appendingPathComponent("homes/\(homeID)/rooms")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["room_id": roomID.uuidString])
        let (_, _) = try await session.data(for: request)
    }

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
                resultType: "detected",
                confidence: candidate.score,
                confidenceState: .liveSeen,
                worldTransform: candidate.worldTransform,
                roomID: nil,
                roomName: nil,
                placeID: nil,
                recencySeconds: nil,
                memoryFreshness: nil,
                routeHint: nil,
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

    func searchHome(
        homeID: String,
        query: String,
        currentRoomID: UUID? = nil,
        currentPlaceID: String? = nil
    ) async throws -> BackendQueryResponse {
        let url = baseURL.appendingPathComponent("homes/\(homeID)/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["query_text": query]
        if let currentRoomID {
            payload["current_room_id"] = currentRoomID.uuidString
        }
        if let currentPlaceID {
            payload["current_place_id"] = currentPlaceID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: request)
        return try decoder.decode(BackendQueryResponse.self, from: data)
    }

    func createOutdoorSession() async throws -> UUID {
        let url = baseURL.appendingPathComponent("outdoor/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["name": "outdoor-session"])
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        guard let idString = decoded["sessionId"], let id = UUID(uuidString: idString) else {
            throw BackendClientError.requestFailed(statusCode: 0, message: "Missing sessionId")
        }
        return id
    }

    func uploadOutdoorFrame(
        sessionID: UUID,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        timestamp: Date,
        imageBase64: String? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("outdoor/sessions/\(sessionID.uuidString)/frames")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "lat": latitude,
            "lng": longitude,
            "accuracy": accuracy,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let imageBase64 { body["image_base64"] = imageBase64 }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await session.data(for: request)
    }

    func searchOutdoorSession(sessionID: UUID, query: String) async throws -> [[String: Any]] {
        let url = baseURL.appendingPathComponent("outdoor/sessions/\(sessionID.uuidString)/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query_text": query])
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return decoded?["matches"] as? [[String: Any]] ?? []
    }

    func getOutdoorDetections(sessionID: UUID) async throws -> [[String: Any]] {
        let url = baseURL.appendingPathComponent("outdoor/sessions/\(sessionID.uuidString)/detections")
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return decoded?["detections"] as? [[String: Any]] ?? []
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

    private func ensureSuccessfulResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw BackendClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

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

private struct CreateHomeResponse: Decodable {
    let homeID: String

    private enum CodingKeys: String, CodingKey {
        case homeID
        case home_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeID =
            try container.decodeIfPresent(String.self, forKey: .homeID) ??
            (try container.decodeIfPresent(String.self, forKey: .home_id)) ??
            ""
    }
}

private struct ReconstructionStatusResponse: Decodable {
    let status: String
}

private enum BackendClientError: LocalizedError {
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let message):
            return "Backend request failed (\(statusCode)): \(message)"
        }
    }
}

struct BackendSearchResult: Decodable, Identifiable {
    let id: UUID
    let label: String
    let resultType: String
    let confidence: Double
    let confidenceState: SearchConfidenceState
    let worldTransform: [Float]?
    let roomID: String?
    let roomName: String?
    let placeID: String?
    let recencySeconds: Double?
    let memoryFreshness: Double?
    let routeHint: String?
    let evidence: [String]
    let explanation: String

    init(
        id: UUID,
        label: String,
        resultType: String,
        confidence: Double,
        confidenceState: SearchConfidenceState,
        worldTransform: [Float]?,
        roomID: String?,
        roomName: String?,
        placeID: String?,
        recencySeconds: Double?,
        memoryFreshness: Double?,
        routeHint: String?,
        evidence: [String],
        explanation: String
    ) {
        self.id = id
        self.label = label
        self.resultType = resultType
        self.confidence = confidence
        self.confidenceState = confidenceState
        self.worldTransform = worldTransform
        self.roomID = roomID
        self.roomName = roomName
        self.placeID = placeID
        self.recencySeconds = recencySeconds
        self.memoryFreshness = memoryFreshness
        self.routeHint = routeHint
        self.evidence = evidence
        self.explanation = explanation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case resultType
        case result_type
        case confidence
        case score
        case confidenceState
        case confidence_state
        case worldTransform
        case world_transform
        case worldTransform16
        case world_transform16
        case roomID
        case room_id
        case roomName
        case room_name
        case placeID
        case place_id
        case recencySeconds
        case recency_seconds
        case memoryFreshness
        case memory_freshness
        case routeHint
        case route_hint
        case evidence
        case explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "result"
        resultType =
            try container.decodeIfPresent(String.self, forKey: .resultType) ??
            (try container.decodeIfPresent(String.self, forKey: .result_type)) ??
            "detected"
        confidence =
            try container.decodeIfPresent(Double.self, forKey: .confidence) ??
            (try container.decodeIfPresent(Double.self, forKey: .score)) ??
            0
        confidenceState =
            (try? container.decodeIfPresent(SearchConfidenceState.self, forKey: .confidenceState)) ??
            (try? container.decodeIfPresent(SearchConfidenceState.self, forKey: .confidence_state)) ??
            (resultType == "stale_memory" ? .staleMemory : (resultType == "last_seen" ? .lastSeen : .liveSeen))
        worldTransform =
            try container.decodeIfPresent([Float].self, forKey: .worldTransform) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform)) ??
            (try container.decodeIfPresent([Float].self, forKey: .worldTransform16)) ??
            (try container.decodeIfPresent([Float].self, forKey: .world_transform16))
        roomID =
            try container.decodeIfPresent(String.self, forKey: .roomID) ??
            (try container.decodeIfPresent(String.self, forKey: .room_id))
        roomName =
            try container.decodeIfPresent(String.self, forKey: .roomName) ??
            (try container.decodeIfPresent(String.self, forKey: .room_name))
        placeID =
            try container.decodeIfPresent(String.self, forKey: .placeID) ??
            (try container.decodeIfPresent(String.self, forKey: .place_id))
        recencySeconds =
            try container.decodeIfPresent(Double.self, forKey: .recencySeconds) ??
            (try container.decodeIfPresent(Double.self, forKey: .recency_seconds))
        memoryFreshness =
            try container.decodeIfPresent(Double.self, forKey: .memoryFreshness) ??
            (try container.decodeIfPresent(Double.self, forKey: .memory_freshness))
        routeHint =
            try container.decodeIfPresent(String.self, forKey: .routeHint) ??
            (try container.decodeIfPresent(String.self, forKey: .route_hint))
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

private struct WearableFrameBatchRequest: Encodable {
    let events: [WearableFrameUpload]
}

struct WearableFrameUploadResponse: Decodable {
    let sessionID: String
    let status: String
    let accepted: Int
    let newFrames: Int
    let duplicateFrames: Int
    let frameCount: Int
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case session_id
        case status
        case accepted
        case newFrames
        case new_frames
        case duplicateFrames
        case duplicate_frames
        case frameCount
        case frame_count
        case updatedAt
        case updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            try container.decodeIfPresent(String.self, forKey: .sessionID) ??
            (try container.decodeIfPresent(String.self, forKey: .session_id)) ??
            ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        accepted = try container.decodeIfPresent(Int.self, forKey: .accepted) ?? 0
        newFrames =
            try container.decodeIfPresent(Int.self, forKey: .newFrames) ??
            (try container.decodeIfPresent(Int.self, forKey: .new_frames)) ??
            0
        duplicateFrames =
            try container.decodeIfPresent(Int.self, forKey: .duplicateFrames) ??
            (try container.decodeIfPresent(Int.self, forKey: .duplicate_frames)) ??
            0
        frameCount =
            try container.decodeIfPresent(Int.self, forKey: .frameCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .frame_count)) ??
            0
        updatedAt =
            try container.decodeIfPresent(String.self, forKey: .updatedAt) ??
            (try container.decodeIfPresent(String.self, forKey: .updated_at))
    }
}

struct WearableSessionStatusResponse: Decodable {
    let sessionID: String
    let homeID: String?
    let deviceName: String?
    let source: String?
    let status: String
    let samplingFps: Double?
    let frameCount: Int
    let storagePath: String?
    let lastFrameID: String?
    let lastFrameTimestamp: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case session_id
        case homeID
        case home_id
        case deviceName
        case device_name
        case source
        case status
        case samplingFps
        case sampling_fps
        case frameCount
        case frame_count
        case storagePath
        case storage_path
        case lastFrameID
        case last_frame_id
        case lastFrameTimestamp
        case last_frame_timestamp
        case updatedAt
        case updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            try container.decodeIfPresent(String.self, forKey: .sessionID) ??
            (try container.decodeIfPresent(String.self, forKey: .session_id)) ??
            ""
        homeID =
            try container.decodeIfPresent(String.self, forKey: .homeID) ??
            (try container.decodeIfPresent(String.self, forKey: .home_id))
        deviceName =
            try container.decodeIfPresent(String.self, forKey: .deviceName) ??
            (try container.decodeIfPresent(String.self, forKey: .device_name))
        source = try container.decodeIfPresent(String.self, forKey: .source)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        samplingFps =
            try container.decodeIfPresent(Double.self, forKey: .samplingFps) ??
            (try container.decodeIfPresent(Double.self, forKey: .sampling_fps))
        frameCount =
            try container.decodeIfPresent(Int.self, forKey: .frameCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .frame_count)) ??
            0
        storagePath =
            try container.decodeIfPresent(String.self, forKey: .storagePath) ??
            (try container.decodeIfPresent(String.self, forKey: .storage_path))
        lastFrameID =
            try container.decodeIfPresent(String.self, forKey: .lastFrameID) ??
            (try container.decodeIfPresent(String.self, forKey: .last_frame_id))
        lastFrameTimestamp =
            try container.decodeIfPresent(String.self, forKey: .lastFrameTimestamp) ??
            (try container.decodeIfPresent(String.self, forKey: .last_frame_timestamp))
        updatedAt =
            try container.decodeIfPresent(String.self, forKey: .updatedAt) ??
            (try container.decodeIfPresent(String.self, forKey: .updated_at))
    }
}

struct HomeTopologyNode: Decodable, Identifiable {
    let id: String
    let displayName: String
    let frameCount: Int
    let roomID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case display_name
        case frameCount
        case frame_count
        case roomID
        case room_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName =
            try container.decodeIfPresent(String.self, forKey: .displayName) ??
            (try container.decodeIfPresent(String.self, forKey: .display_name)) ??
            id
        frameCount =
            try container.decodeIfPresent(Int.self, forKey: .frameCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .frame_count)) ??
            0
        roomID =
            try container.decodeIfPresent(String.self, forKey: .roomID) ??
            (try container.decodeIfPresent(String.self, forKey: .room_id))
    }
}

struct HomeTopologyEdge: Decodable, Identifiable {
    let id: String
    let sourcePlaceID: String
    let targetPlaceID: String
    let transitionCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case sourcePlaceID
        case source_place_id
        case targetPlaceID
        case target_place_id
        case transitionCount
        case transition_count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourcePlaceID =
            try container.decodeIfPresent(String.self, forKey: .sourcePlaceID) ??
            (try container.decodeIfPresent(String.self, forKey: .source_place_id)) ??
            ""
        targetPlaceID =
            try container.decodeIfPresent(String.self, forKey: .targetPlaceID) ??
            (try container.decodeIfPresent(String.self, forKey: .target_place_id)) ??
            ""
        transitionCount =
            try container.decodeIfPresent(Int.self, forKey: .transitionCount) ??
            (try container.decodeIfPresent(Int.self, forKey: .transition_count)) ??
            0
    }
}

struct HomeTopologyResponse: Decodable {
    let homeID: String
    let nodes: [HomeTopologyNode]
    let edges: [HomeTopologyEdge]

    private enum CodingKeys: String, CodingKey {
        case homeID
        case home_id
        case nodes
        case edges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeID =
            try container.decodeIfPresent(String.self, forKey: .homeID) ??
            (try container.decodeIfPresent(String.self, forKey: .home_id)) ??
            ""
        nodes = try container.decodeIfPresent([HomeTopologyNode].self, forKey: .nodes) ?? []
        edges = try container.decodeIfPresent([HomeTopologyEdge].self, forKey: .edges) ?? []
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
