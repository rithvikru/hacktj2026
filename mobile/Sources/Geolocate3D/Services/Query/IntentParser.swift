import Foundation

/// Parsed query intent from natural language.
struct QueryIntent {
    enum IntentType {
        case findObject(label: String)
        case listObjects(category: String?)
        case describeLocation(label: String)
        case spatialRelation(subject: String, relation: String, reference: String)
        case freeform(text: String)
    }

    let type: IntentType
    let rawQuery: String
    let roomScope: UUID?
}

/// Parses natural language queries into structured intents.
/// Uses keyword matching as a baseline; can be upgraded to ML-based parsing.
struct IntentParser {
    private static let findPrefixes = ["where is", "where are", "find", "locate", "show me", "where did i"]
    private static let listPrefixes = ["list", "show all", "what's on", "what is on", "what are"]
    private static let spatialKeywords = ["near", "next to", "on top of", "under", "behind", "in front of", "inside", "on"]
    private static let leadingNoiseWords = Set(["my", "the", "a", "an", "please"])

    func parse(_ query: String, roomID: UUID? = nil) -> QueryIntent {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Find/locate intent
        for prefix in Self.findPrefixes {
            if normalized.hasPrefix(prefix) {
                let label = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
                let cleanedLabel = sanitizeEntityText(label)
                if !cleanedLabel.isEmpty {
                    return QueryIntent(type: .findObject(label: cleanedLabel), rawQuery: query, roomScope: roomID)
                }
            }
        }

        // List intent
        for prefix in Self.listPrefixes {
            if normalized.hasPrefix(prefix) {
                let category = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
                let cleanedCategory = sanitizeEntityText(category)
                return QueryIntent(
                    type: .listObjects(category: cleanedCategory.isEmpty ? nil : cleanedCategory),
                    rawQuery: query,
                    roomScope: roomID
                )
            }
        }

        // Spatial relation intent
        for keyword in Self.spatialKeywords {
            if let range = normalized.range(of: " \(keyword) ") {
                let subject = String(normalized[normalized.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let reference = String(normalized[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
                let cleanedSubject = sanitizeEntityText(subject)
                let cleanedReference = sanitizeEntityText(reference)
                if !cleanedSubject.isEmpty && !cleanedReference.isEmpty {
                    return QueryIntent(
                        type: .spatialRelation(subject: cleanedSubject, relation: keyword, reference: cleanedReference),
                        rawQuery: query,
                        roomScope: roomID
                    )
                }
            }
        }

        // Fallback: freeform
        return QueryIntent(type: .freeform(text: normalized), rawQuery: query, roomScope: roomID)
    }

    private func sanitizeEntityText(_ text: String) -> String {
        let components = text
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
        let cleaned = components.drop(while: { Self.leadingNoiseWords.contains($0) })
        return cleaned.joined(separator: " ")
    }
}
