import Foundation

struct QueryHistoryEntry: Identifiable {
    let id: UUID
    let query: String
    let resultSummary: String
    let timestamp: Date
}

@Observable
@MainActor
final class QueryViewModel {
    var currentResult: SearchResult?
    var history: [QueryHistoryEntry] = []
    var isListening = false
    var transcribedText = ""
    var isProcessing = false

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

    func execute(query: String, roomID: UUID?) async {
        guard !query.isEmpty else { return }
        isProcessing = true

        let intent = intentParser.parse(query)

        let result = await searchPlanner.execute(intent: intent, roomID: roomID)

        currentResult = result

        history.insert(QueryHistoryEntry(
            id: UUID(),
            query: query,
            resultSummary: result.explanation,
            timestamp: Date()
        ), at: 0)

        if history.count > 20 {
            history = Array(history.prefix(20))
        }

        isProcessing = false
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
