import Foundation

enum ExecutorType {
    case localObservation, sceneGraph, hiddenInference, backend
}

struct SearchPlan {
    let executorType: ExecutorType
    let intent: QueryIntent
    let roomID: UUID?
}

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

    func execute(intent: QueryIntent, roomID: UUID?) async -> SearchResult {
        let plan = Self.plan(intent: intent, roomID: roomID)

        switch plan.executorType {
        case .localObservation, .sceneGraph, .backend, .hiddenInference:
            return await executeLocal(intent: intent, roomID: roomID)
        }
    }

    private func executeLocal(intent: QueryIntent, roomID: UUID?) async -> SearchResult {
        switch intent.type {
        case .findObject(let label):
            return await localExecutor.findObject(label: label, roomID: roomID, rawQuery: intent.rawQuery)
        case .listObjects(let category):
            return await localExecutor.listObjects(category: category, roomID: roomID, rawQuery: intent.rawQuery)
        case .describeLocation(let label):
            return await localExecutor.describeLocation(label: label, roomID: roomID, rawQuery: intent.rawQuery)
        case .spatialRelation(let subject, let relation, let reference):
            return await localExecutor.spatialRelation(
                subject: subject, relation: relation, reference: reference,
                roomID: roomID, rawQuery: intent.rawQuery
            )
        case .freeform(let text):
            return await localExecutor.freeformSearch(text: text, roomID: roomID, rawQuery: intent.rawQuery)
        }
    }
}
