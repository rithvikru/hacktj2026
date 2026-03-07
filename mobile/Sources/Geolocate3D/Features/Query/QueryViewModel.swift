import Foundation
import SwiftData

/// History entry for past queries.
struct QueryHistoryEntry: Identifiable {
    let id: UUID
    let query: String
    let resultSummary: String
    let timestamp: Date
}

struct QueryConversationEntry: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let subtitle: String?
}

@Observable
@MainActor
final class QueryViewModel {
    var currentResult: SearchResult?
    var history: [QueryHistoryEntry] = []
    var isListening = false
    var transcribedText = ""
    var isProcessing = false
    var conversation: [QueryConversationEntry] = []

    let suggestions = [
        "Where are my keys?",
        "How many chairs?",
        "Show me the wallet",
        "What's near the bed?",
        "Find the remote"
    ]

    private let speechService = SpeechRecognitionService()
    private let intentParser = IntentParser()
    private let searchPlanner = SearchPlanner()

    func toggleVoiceInput() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func execute(query: String, roomID: UUID?, modelContext: ModelContext, backendClient: BackendClient) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isProcessing = true
        conversation.append(
            QueryConversationEntry(
                id: UUID(),
                role: .user,
                content: trimmedQuery,
                subtitle: nil
            )
        )

        // Parse intent
        let intent = intentParser.parse(trimmedQuery, roomID: roomID)

        // Plan and execute search
        let execution = await searchPlanner.execute(
            intent: intent,
            roomID: roomID,
            modelContext: modelContext,
            backendClient: backendClient
        )
        let result = execution.result

        currentResult = result
        await generateAssistantReply(
            query: trimmedQuery,
            roomID: roomID,
            result: result,
            backendClient: backendClient
        )

        // Add to history
        history.insert(QueryHistoryEntry(
            id: UUID(),
            query: trimmedQuery,
            resultSummary: result.explanation,
            timestamp: Date()
        ), at: 0)

        // Keep history bounded
        if history.count > 20 {
            history = Array(history.prefix(20))
        }

        isProcessing = false
    }

    private func generateAssistantReply(
        query: String,
        roomID: UUID?,
        result: SearchResult,
        backendClient: BackendClient
    ) async {
        guard let roomID else {
            conversation.append(
                QueryConversationEntry(
                    id: UUID(),
                    role: .assistant,
                    content: result.explanation,
                    subtitle: "Local"
                )
            )
            trimConversation()
            return
        }

        do {
            let priorMessages = conversation.map { entry in
                BackendChatMessage(
                    role: entry.role == .user ? .user : .assistant,
                    content: entry.content
                )
            }
            let response = try await backendClient.chat(
                roomID: roomID,
                query: query,
                messages: priorMessages
            )
            conversation.append(
                QueryConversationEntry(
                    id: UUID(),
                    role: .assistant,
                    content: response.reply.content,
                    subtitle: "\(response.provider) • \(response.model)"
                )
            )
        } catch {
            conversation.append(
                QueryConversationEntry(
                    id: UUID(),
                    role: .assistant,
                    content: result.explanation,
                    subtitle: "Fallback"
                )
            )
        }
        trimConversation()
    }

    private func trimConversation() {
        if conversation.count > 12 {
            conversation = Array(conversation.suffix(12))
        }
    }

    private func startListening() {
        isListening = true
        transcribedText = ""
        speechService.startRecognition { [weak self] text in
            Task { @MainActor in
                self?.transcribedText = text
            }
        }
    }

    private func stopListening() {
        isListening = false
        speechService.stopRecognition()
    }
}
