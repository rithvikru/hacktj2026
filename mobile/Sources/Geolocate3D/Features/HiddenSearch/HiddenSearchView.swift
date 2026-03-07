import SwiftUI
import SwiftData

struct HiddenSearchView: View {
    let roomID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HiddenSearchViewModel
    @State private var selectedHypothesis: ObjectHypothesis?
    @State private var queryText = ""
    @FocusState private var isQueryFocused: Bool

    init(roomID: UUID) {
        self.roomID = roomID
        _viewModel = State(initialValue: HiddenSearchViewModel(roomID: roomID))
    }

    var body: some View {
        ZStack {
            RoomHeatmapView(
                roomID: roomID,
                hypotheses: viewModel.hypotheses,
                selectedID: selectedHypothesis?.id
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("What are you trying to uncover?", text: $queryText)
                        .font(SpatialFont.body)
                        .foregroundStyle(.white)
                        .tint(.inferenceViolet)
                        .focused($isQueryFocused)
                        .onSubmit { submitHiddenSearch() }

                    Button(action: submitHiddenSearch) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.black)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.inferenceViolet, in: Circle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if viewModel.hypotheses.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hiddenQuerySuggestions, id: \.self) { suggestion in
                                Button {
                                    queryText = suggestion
                                    submitHiddenSearch()
                                } label: {
                                    Text(suggestion)
                                        .font(SpatialFont.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.glassWhite, in: Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()
            }

            // Ranked hypothesis cards
            VStack {
                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.hypotheses) { hypothesis in
                            HypothesisCard(
                                hypothesis: hypothesis,
                                isSelected: hypothesis.id == selectedHypothesis?.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35)) {
                                    selectedHypothesis = hypothesis
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 160)
                .padding(.bottom, 24)
            }

            // Disclaimer for inferred locations
            if viewModel.hypotheses.contains(where: { $0.hypothesisType == .inferred }) {
                VStack {
                    HStack {
                        Spacer()
                        Label("Estimated locations", systemImage: "exclamationmark.triangle")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.warningAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            // Empty state
            if viewModel.hypotheses.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.inferenceViolet)
                    Text("No hypotheses yet")
                        .font(SpatialFont.headline)
                        .foregroundStyle(.white)
                    Text("Search for a hidden object to generate location estimates.")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
        }
        .navigationTitle("Hidden Search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.loadHypotheses(modelContext: modelContext)
        }
    }

    private var hiddenQuerySuggestions: [String] {
        [
            "wallet",
            "passport",
            "charger",
            "headphones",
            "remote"
        ]
    }

    private func submitHiddenSearch() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isQueryFocused = false
        Task {
            await viewModel.runInference(query: query, modelContext: modelContext)
            selectedHypothesis = viewModel.hypotheses.first
        }
    }
}
