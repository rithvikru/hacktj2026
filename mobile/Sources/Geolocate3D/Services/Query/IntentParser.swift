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

    func parse(_ query: String, roomID: UUID? = nil) -> QueryIntent {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Find/locate intent
        for prefix in Self.findPrefixes {
            if normalized.hasPrefix(prefix) {
                let label = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
                if !label.isEmpty {
                    return QueryIntent(type: .findObject(label: label), rawQuery: query, roomScope: roomID)
                }
            }
        }

        // List intent
        for prefix in Self.listPrefixes {
            if normalized.hasPrefix(prefix) {
                let category = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
                return QueryIntent(
                    type: .listObjects(category: category.isEmpty ? nil : category),
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
                if !subject.isEmpty && !reference.isEmpty {
                    return QueryIntent(
                        type: .spatialRelation(subject: subject, relation: keyword, reference: reference),
                        rawQuery: query,
                        roomScope: roomID
                    )
                }
            }
        }

        // Fallback: freeform
        return QueryIntent(type: .freeform(text: normalized), rawQuery: query, roomScope: roomID)
    }
}
