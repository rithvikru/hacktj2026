import SwiftUI

struct QueryConsoleView: View {
    let roomID: UUID?
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
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(viewModel.isListening ? .black : .white)
                            .frame(width: 44, height: 44)
                            .background(viewModel.isListening ? Color.spatialCyan : .glassWhite)
                            .clipShape(Circle())
                    }

                    if viewModel.isListening {
                        AnimatedWaveform()
                            .frame(height: 24)
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
                                .font(.system(size: 32))
                                .foregroundStyle(.spatialCyan)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Color.glassEdge)

                // Results / History
                ScrollView {
                    if let result = viewModel.currentResult {
                        QueryResultView(result: result)
                            .padding(16)
                    }

                    // Suggestions
                    if viewModel.currentResult == nil && queryText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
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
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.glassWhite, in: Capsule())
                                }
                            }
                        }
                        .padding(.top, 16)
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
                        .padding(.top, 24)
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
            await viewModel.execute(query: text, roomID: roomID)
        }
    }
}
