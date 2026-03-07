import Foundation
import SwiftData

struct SearchExecutionResult {
    let result: SearchResult
    let localObservations: [ObjectObservation]
    let backendResults: [BackendSearchResult]
}

/// Executor routing classification.
enum ExecutorType {
    case localObservation, sceneGraph, hiddenInference, backend
}

/// Planned search execution.
struct SearchPlan {
    let executorType: ExecutorType
    let intent: QueryIntent
    let roomID: UUID?
}

/// Routes parsed query intents to the appropriate executor and returns results.
struct SearchPlanner {
    private let localExecutor = LocalObservationExecutor()

    static func plan(intent: QueryIntent, roomID: UUID?) -> SearchPlan {
        let executorType: ExecutorType
        switch intent.type {
        case .findObject, .listObjects, .describeLocation:
            executorType = .localObservation
        case .spatialRelation:
            executorType = .sceneGraph
        case .freeform:
            executorType = .backend
        }
        return SearchPlan(executorType: executorType, intent: intent, roomID: roomID)
    }

    @MainActor
    func execute(
        intent: QueryIntent,
        roomID: UUID?,
        modelContext: ModelContext,
        backendClient: BackendClient? = nil
    ) async -> SearchExecutionResult {
        let plan = Self.plan(intent: intent, roomID: roomID)

        switch plan.executorType {
        case .localObservation:
            return await executeFindObject(intent: intent, roomID: roomID, modelContext: modelContext, backendClient: backendClient)
        case .sceneGraph:
            return executeSceneGraph(intent: intent, roomID: roomID, modelContext: modelContext)
        case .backend:
            return await executeBackend(intent: intent, roomID: roomID, modelContext: modelContext, backendClient: backendClient)
        case .hiddenInference:
            return await executeFindObject(intent: intent, roomID: roomID, modelContext: modelContext, backendClient: backendClient)
        }
    }

    @MainActor
    private func executeFindObject(
        intent: QueryIntent,
        roomID: UUID?,
        modelContext: ModelContext,
        backendClient: BackendClient?
    ) async -> SearchExecutionResult {
        switch intent.type {
        case .findObject(let label):
            let localResult = localExecutor.findObject(
                label: label,
                roomID: roomID,
                rawQuery: intent.rawQuery,
                modelContext: modelContext
            )
            if localResult.result.resultType != .noResult {
                return SearchExecutionResult(
                    result: localResult.result,
                    localObservations: localResult.observations,
                    backendResults: []
                )
            }
            return await executeBackendSearch(
                queryText: label,
                rawQuery: intent.rawQuery,
                roomID: roomID,
                fallback: localResult.result,
                backendClient: backendClient
            )
        case .listObjects(let category):
            let localResult = localExecutor.listObjects(
                category: category,
                roomID: roomID,
                rawQuery: intent.rawQuery,
                modelContext: modelContext
            )
            return SearchExecutionResult(result: localResult.result, localObservations: localResult.observations, backendResults: [])
        case .describeLocation(let label):
            let localResult = localExecutor.describeLocation(
                label: label,
                roomID: roomID,
                rawQuery: intent.rawQuery,
                modelContext: modelContext
            )
            if localResult.result.resultType != .noResult {
                return SearchExecutionResult(result: localResult.result, localObservations: localResult.observations, backendResults: [])
            }
            return await executeBackendSearch(
                queryText: label,
                rawQuery: intent.rawQuery,
                roomID: roomID,
                fallback: localResult.result,
                backendClient: backendClient
            )
        default:
            return await executeBackend(intent: intent, roomID: roomID, modelContext: modelContext, backendClient: backendClient)
        }
    }

    @MainActor
    private func executeSceneGraph(intent: QueryIntent, roomID: UUID?, modelContext: ModelContext) -> SearchExecutionResult {
        switch intent.type {
        case .spatialRelation(let subject, let relation, let reference):
            let localResult = localExecutor.spatialRelation(
                subject: subject, relation: relation, reference: reference,
                roomID: roomID, rawQuery: intent.rawQuery, modelContext: modelContext
            )
            return SearchExecutionResult(result: localResult.result, localObservations: localResult.observations, backendResults: [])
        default:
            let result = SearchResult(
                id: UUID(),
                query: intent.rawQuery,
                resultType: .noResult,
                label: intent.rawQuery,
                confidence: 0,
                explanation: "Scene-graph search is only available for spatial-relation queries.",
                evidence: [],
                timestamp: Date()
            )
            return SearchExecutionResult(result: result, localObservations: [], backendResults: [])
        }
    }

    @MainActor
    private func executeBackend(
        intent: QueryIntent,
        roomID: UUID?,
        modelContext: ModelContext,
        backendClient: BackendClient?
    ) async -> SearchExecutionResult {
        switch intent.type {
        case .freeform(let text):
            let localResult = localExecutor.freeformSearch(
                text: text,
                roomID: roomID,
                rawQuery: intent.rawQuery,
                modelContext: modelContext
            )
            if localResult.result.resultType != .noResult {
                return SearchExecutionResult(result: localResult.result, localObservations: localResult.observations, backendResults: [])
            }
            return await executeBackendSearch(
                queryText: text,
                rawQuery: intent.rawQuery,
                roomID: roomID,
                fallback: localResult.result,
                backendClient: backendClient
            )
        case .findObject, .listObjects, .describeLocation, .spatialRelation:
            return await executeFindObject(intent: intent, roomID: roomID, modelContext: modelContext, backendClient: backendClient)
        }
    }

    @MainActor
    private func executeBackendSearch(
        queryText: String,
        rawQuery: String,
        roomID: UUID?,
        fallback: SearchResult,
        backendClient: BackendClient?
    ) async -> SearchExecutionResult {
        guard let roomID, let backendClient else {
            return SearchExecutionResult(result: fallback, localObservations: [], backendResults: [])
        }

        do {
            let queryResponse = try await backendClient.queryRoom(roomID: roomID, query: queryText)
            if !queryResponse.results.isEmpty {
                let result = makeBackendSummary(
                    query: rawQuery,
                    label: queryText,
                    results: queryResponse.results,
                    explanation: queryResponse.explanation
                )
                return SearchExecutionResult(result: result, localObservations: [], backendResults: queryResponse.results)
            }

            let openVocabResults = try await backendClient.openVocabSearch(roomID: roomID, query: queryText)
            guard !openVocabResults.isEmpty else {
                return SearchExecutionResult(result: fallback, localObservations: [], backendResults: [])
            }

            let result = makeBackendSummary(
                query: rawQuery,
                label: queryText,
                results: openVocabResults,
                explanation: "Found \(openVocabResults.count) backend candidate\(openVocabResults.count == 1 ? "" : "s")."
            )
            return SearchExecutionResult(result: result, localObservations: [], backendResults: openVocabResults)
        } catch {
            let errorResult = SearchResult(
                id: UUID(),
                query: rawQuery,
                resultType: .noResult,
                label: queryText,
                confidence: 0,
                explanation: "Backend search failed: \(error.localizedDescription)",
                evidence: ["backend-search"],
                timestamp: Date()
            )
            return SearchExecutionResult(result: errorResult, localObservations: [], backendResults: [])
        }
    }

    private func makeBackendSummary(
        query: String,
        label: String,
        results: [BackendSearchResult],
        explanation: String
    ) -> SearchResult {
        let top = results[0]
        let resultType: DetectionConfidenceClass
        if top.worldTransform != nil {
            resultType = top.confidence >= 0.8 ? .confirmedHigh : .confirmedMedium
        } else {
            resultType = .confirmedMedium
        }
        return SearchResult(
            id: top.id,
            query: query,
            resultType: resultType,
            label: top.label.isEmpty ? label : top.label,
            confidence: top.confidence,
            explanation: explanation.isEmpty ? top.explanation : explanation,
            evidence: top.evidence.isEmpty ? ["backend-search"] : top.evidence,
            timestamp: Date()
        )
    }
}
