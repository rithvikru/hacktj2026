import SwiftUI

struct QueryConsoleView: View {
    let roomID: UUID?
    var onFocusSemanticObject: ((String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(BackendClient.self) private var backendClient
    @State private var viewModel = QueryViewModel()
    @State private var queryText = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Query input area
                HStack(spacing: 12) {
                    // Mic button
                    Button {
                        viewModel.toggleVoiceInput()
                    } label: {
                        Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(viewModel.isListening ? .white : .dimLabel)
                            .frame(width: 40, height: 40)
                            .background(viewModel.isListening ? Color.spatialCyan.opacity(0.8) : Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }

                    if viewModel.isListening {
                        AnimatedWaveform()
                            .frame(height: 20)
                    } else {
                        TextField("Where are my keys?", text: $queryText)
                            .font(SpatialFont.body)
                            .foregroundStyle(.white)
                            .tint(.spatialCyan)
                            .focused($isTextFocused)
                            .onSubmit {
                                submitQuery()
                            }
                    }

                    Spacer(minLength: 0)

                    if !queryText.isEmpty {
                        Button {
                            submitQuery()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.spatialCyan)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 0.5)

                // Results / History
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !viewModel.conversation.isEmpty {
                            ForEach(viewModel.conversation) { entry in
                                QueryConversationBubble(entry: entry)
                            }
                        }

                        if let result = viewModel.currentResult {
                            QueryResultView(result: result)
                                .onTapGesture {
                                    // When tapped, focus nearest semantic object
                                    if let focusHandler = onFocusSemanticObject {
                                        focusHandler(result.label)
                                    }
                                }
                        }

                        if viewModel.isProcessing {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.spatialCyan)
                                Text("Thinking through the room...")
                                    .font(SpatialFont.caption)
                                    .foregroundStyle(.dimLabel)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(16)

                    // Suggestions
                    if viewModel.currentResult == nil && queryText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggestions")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                                .padding(.horizontal, 16)

                            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                                Button {
                                    queryText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(SpatialFont.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    // Query history
                    if !viewModel.history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                                .padding(.horizontal, 16)
                            ForEach(viewModel.history) { entry in
                                QueryHistoryRow(entry: entry)
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
            .background(Color.obsidian)
            .navigationTitle("Query")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.transcribedText) { _, newText in
            if !newText.isEmpty {
                queryText = newText
            }
        }
    }

    private func submitQuery() {
        let text = queryText
        queryText = ""
        Task {
            await viewModel.execute(
                query: text,
                roomID: roomID,
                modelContext: modelContext,
                backendClient: backendClient
            )
        }
    }
}

private struct QueryConversationBubble: View {
    let entry: QueryConversationEntry

    var body: some View {
        VStack(alignment: entry.role == .user ? .trailing : .leading, spacing: 4) {
            Text(entry.role == .user ? "You" : "Assistant")
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)

            Text(entry.content)
                .font(SpatialFont.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: entry.role == .user ? .trailing : .leading)

            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: entry.role == .user ? .trailing : .leading)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, entry.role == .user ? 40 : 0)
    }

    private var bubbleBackground: AnyShapeStyle {
        if entry.role == .user {
            return AnyShapeStyle(Color.spatialCyan.opacity(0.1))
        }
        return AnyShapeStyle(Color.elevatedSurface)
    }
}
