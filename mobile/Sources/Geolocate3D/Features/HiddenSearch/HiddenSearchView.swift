import SwiftUI

struct HiddenSearchView: View {
    let roomID: UUID
    @Environment(RoomStore.self) private var roomStore
    @State private var viewModel: HiddenSearchViewModel
    @State private var selectedHypothesis: ObjectHypothesis?

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
            viewModel.loadHypotheses(roomStore: roomStore)
        }
    }
}
