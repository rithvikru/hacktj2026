import Foundation

struct LocalObservationExecutor {

    func findObject(label: String, roomID: UUID?, rawQuery: String) async -> SearchResult {

        SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .lastSeen,
            label: label,
            confidence: 0.0,
            explanation: "Searching for \"\(label)\" in local observations...",
            evidence: ["local-observation-store"],
            timestamp: Date()
        )
    }

    func listObjects(category: String?, roomID: UUID?, rawQuery: String) async -> SearchResult {
        let desc = category ?? "all objects"
        return SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .confirmedMedium,
            label: desc,
            confidence: 0.0,
            explanation: "Listing \(desc)...",
            evidence: ["local-observation-store"],
            timestamp: Date()
        )
    }

    func describeLocation(label: String, roomID: UUID?, rawQuery: String) async -> SearchResult {
        SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .confirmedMedium,
            label: label,
            confidence: 0.0,
            explanation: "Describing location of \"\(label)\"...",
            evidence: ["local-observation-store"],
            timestamp: Date()
        )
    }

    func spatialRelation(subject: String, relation: String, reference: String,
                         roomID: UUID?, rawQuery: String) async -> SearchResult {

        SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .confirmedMedium,
            label: subject,
            confidence: 0.0,
            explanation: "Looking for \"\(subject)\" \(relation) \"\(reference)\"...",
            evidence: ["scene-graph"],
            timestamp: Date()
        )
    }

    func freeformSearch(text: String, roomID: UUID?, rawQuery: String) async -> SearchResult {

        SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .noResult,
            label: text,
            confidence: 0.0,
            explanation: "Processing query: \"\(text)\"...",
            evidence: [],
            timestamp: Date()
        )
    }
}
