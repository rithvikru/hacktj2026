import Foundation
import simd
import SwiftData

struct LocalObservationSearchResult {
    let result: SearchResult
    let observations: [ObjectObservation]
}

/// Searches local SwiftData observations for query matches.
/// This is the primary executor for on-device queries.
struct LocalObservationExecutor {

    @MainActor
    func findObject(label: String, roomID: UUID?, rawQuery: String, modelContext: ModelContext) -> LocalObservationSearchResult {
        let observations = fetchObservations(roomID: roomID, modelContext: modelContext)
        let matches = matchingObservations(for: label, in: observations)

        guard let topMatch = matches.first else {
            return .init(
                result: makeNoResult(query: rawQuery, label: label, explanation: "No local room-memory match found for \"\(label)\"."),
                observations: []
            )
        }

        let visibilityDescription = topMatch.visibilityState == .visible ? "visible room memory" : "last-seen room memory"
        let result = SearchResult(
            id: topMatch.id,
            query: rawQuery,
            resultType: resultType(for: topMatch),
            label: topMatch.label,
            confidence: topMatch.confidence,
            explanation: "Found \(matches.count) local match\(matches.count == 1 ? "" : "es") for \"\(label)\" from \(visibilityDescription).",
            evidence: ["local-observation-store"],
            timestamp: topMatch.observedAt
        )

        return .init(result: result, observations: Array(matches.prefix(5)))
    }

    @MainActor
    func listObjects(category: String?, roomID: UUID?, rawQuery: String, modelContext: ModelContext) -> LocalObservationSearchResult {
        let observations = fetchObservations(roomID: roomID, modelContext: modelContext)
        let matches = category.map { matchingObservations(for: $0, in: observations) } ?? observations

        guard !matches.isEmpty else {
            return .init(
                result: makeNoResult(
                    query: rawQuery,
                    label: category ?? "objects",
                    explanation: "No local observations are available for that list query."
                ),
                observations: []
            )
        }

        let uniqueLabels = Array(Set(matches.map(\.label))).sorted()
        let preview = uniqueLabels.prefix(3).joined(separator: ", ")
        let label = category ?? "Objects"
        let result = SearchResult(
            id: UUID(),
            query: rawQuery,
            resultType: .confirmedMedium,
            label: label,
            confidence: 1,
            explanation: "Found \(uniqueLabels.count) object type\(uniqueLabels.count == 1 ? "" : "s"): \(preview)",
            evidence: ["local-observation-store"],
            timestamp: matches.first?.observedAt ?? Date()
        )

        return .init(result: result, observations: Array(matches.prefix(5)))
    }

    @MainActor
    func describeLocation(label: String, roomID: UUID?, rawQuery: String, modelContext: ModelContext) -> LocalObservationSearchResult {
        findObject(label: label, roomID: roomID, rawQuery: rawQuery, modelContext: modelContext)
    }

    @MainActor
    func spatialRelation(subject: String, relation: String, reference: String,
                         roomID: UUID?, rawQuery: String, modelContext: ModelContext) -> LocalObservationSearchResult {
        let observations = fetchObservations(roomID: roomID, modelContext: modelContext)
        let subjectMatches = matchingObservations(for: subject, in: observations)
        let referenceMatches = matchingObservations(for: reference, in: observations)

        guard let subjectObservation = subjectMatches.first, let referenceObservation = referenceMatches.first else {
            return .init(
                result: makeNoResult(
                    query: rawQuery,
                    label: subject,
                    explanation: "Could not resolve both \"\(subject)\" and \"\(reference)\" from local room memory."
                ),
                observations: []
            )
        }

        let subjectPosition = subjectObservation.worldTransform.columns.3
        let referencePosition = referenceObservation.worldTransform.columns.3
        let distance = simd_distance(
            SIMD3(subjectPosition.x, subjectPosition.y, subjectPosition.z),
            SIMD3(referencePosition.x, referencePosition.y, referencePosition.z)
        )

        let explanation = "\"\(subjectObservation.label)\" is \(String(format: "%.2f", distance))m \(relation) \"\(referenceObservation.label)\" in saved room coordinates."
        let result = SearchResult(
            id: subjectObservation.id,
            query: rawQuery,
            resultType: resultType(for: subjectObservation),
            label: subjectObservation.label,
            confidence: min(subjectObservation.confidence, referenceObservation.confidence),
            explanation: explanation,
            evidence: ["local-observation-store", "scene-graph-lite"],
            timestamp: max(subjectObservation.observedAt, referenceObservation.observedAt)
        )

        return .init(result: result, observations: [subjectObservation, referenceObservation])
    }

    @MainActor
    func freeformSearch(text: String, roomID: UUID?, rawQuery: String, modelContext: ModelContext) -> LocalObservationSearchResult {
        let observations = fetchObservations(roomID: roomID, modelContext: modelContext)
        let matches = matchingObservations(for: text, in: observations)
        if let topMatch = matches.first {
            let result = SearchResult(
                id: topMatch.id,
                query: rawQuery,
                resultType: resultType(for: topMatch),
                label: topMatch.label,
                confidence: topMatch.confidence,
                explanation: "Matched \"\(text)\" against local room memory.",
                evidence: ["local-observation-store"],
                timestamp: topMatch.observedAt
            )
            return .init(result: result, observations: Array(matches.prefix(5)))
        }

        return .init(
            result: makeNoResult(query: rawQuery, label: text, explanation: "No local match found. Backend search may still help."),
            observations: []
        )
    }

    @MainActor
    private func fetchObservations(roomID: UUID?, modelContext: ModelContext) -> [ObjectObservation] {
        if let roomID {
            let descriptor = FetchDescriptor<ObjectObservation>(
                predicate: #Predicate { $0.room?.id == roomID },
                sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<ObjectObservation>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func matchingObservations(for query: String, in observations: [ObjectObservation]) -> [ObjectObservation] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return observations
            .filter { observation in
                searchableTerms(for: observation).contains { candidate in
                    let normalizedCandidate = normalize(candidate)
                    guard !normalizedCandidate.isEmpty else { return false }
                    return normalizedCandidate == normalizedQuery ||
                        normalizedCandidate.contains(normalizedQuery) ||
                        normalizedQuery.contains(normalizedCandidate)
                }
            }
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.observedAt > $1.observedAt
                }
                return $0.confidence > $1.confidence
            }
    }

    private func searchableTerms(for observation: ObjectObservation) -> [String] {
        var terms = [observation.label]
        if let prototype = observation.prototype {
            terms.append(prototype.canonicalName)
            terms.append(prototype.displayName)
            terms.append(contentsOf: prototype.synonyms)
        }
        return terms
    }

    private func normalize(_ text: String) -> String {
        let sanitizedScalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let raw = String(sanitizedScalars)
        let components = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let cleaned = components.drop(while: { ["my", "the", "a", "an", "please"].contains($0) })
        return cleaned.joined(separator: " ")
    }

    private func resultType(for observation: ObjectObservation) -> DetectionConfidenceClass {
        switch observation.source {
        case .signal:
            return .signalEstimated
        default:
            if observation.visibilityState == .visible {
                return observation.confidence >= 0.8 ? .confirmedHigh : .confirmedMedium
            }
            return .lastSeen
        }
    }

    private func makeNoResult(query: String, label: String, explanation: String) -> SearchResult {
        SearchResult(
            id: UUID(),
            query: query,
            resultType: .noResult,
            label: label,
            confidence: 0,
            explanation: explanation,
            evidence: [],
            timestamp: Date()
        )
    }
}
