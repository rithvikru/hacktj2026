import SwiftData
import SwiftUI

struct ObjectDetailView: View {
    let observationID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var coordinator
    @State private var observation: ObjectObservation?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.obsidian.ignoresSafeArea()

                if let observation {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                ConfidenceIndicator(level: observation.confidenceClass)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(observation.label)
                                        .font(SpatialFont.title2)
                                        .foregroundStyle(.white)
                                    Text(observation.room?.name ?? "Unknown room")
                                        .font(SpatialFont.caption)
                                        .foregroundStyle(.dimLabel)
                                }
                            }

                            detailRow("Confidence", "\(Int(observation.confidence * 100))%")
                            detailRow("Source", observation.source.rawValue)
                            detailRow("Visibility", observation.visibilityState.rawValue)
                            detailRow("Observed", observation.observedAt.formatted(date: .abbreviated, time: .shortened))

                            if let roomID = observation.room?.id {
                                Button {
                                    coordinator.dismissSheet()
                                    coordinator.push(.roomTwin(roomID: roomID))
                                } label: {
                                    Label("Open Room Twin", systemImage: "cube.transparent")
                                        .font(SpatialFont.subheadline)
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.spatialCyan, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.warningAmber)
                        Text("Object memory unavailable")
                            .font(SpatialFont.headline)
                            .foregroundStyle(.white)
                        Text("The selected observation is no longer in local memory.")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Object Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            loadObservation()
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
            Text(value)
                .font(SpatialFont.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassBackground(cornerRadius: 20)
    }

    private func loadObservation() {
        var descriptor = FetchDescriptor<ObjectObservation>(
            predicate: #Predicate { $0.id == observationID }
        )
        descriptor.fetchLimit = 1
        observation = try? modelContext.fetch(descriptor).first
    }
}
