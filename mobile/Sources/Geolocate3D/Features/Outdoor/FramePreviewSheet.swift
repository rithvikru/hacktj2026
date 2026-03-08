import SwiftUI

struct FramePreviewSheet: View {
    let detectionID: UUID
    @Environment(OutdoorSessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var detection: OutdoorDetection? {
        store.detections.first { $0.id == detectionID }
    }

    private var frame: OutdoorFrame? {
        guard let detection else { return nil }
        return store.frame(for: detection.frameID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let detection {

                    if let frame, !frame.imagePath.isEmpty {
                        AsyncImage(url: URL(fileURLWithPath: frame.imagePath)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            placeholderView
                        }
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    } else {
                        placeholderView
                            .frame(height: 200)
                            .padding(.horizontal, 16)
                    }

                    VStack(spacing: 16) {

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detection.label.capitalized)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(String(format: "%.0f%% confidence", detection.confidence * 100))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(detection.confidence >= 0.7 ? .spatialCyan : .warningAmber)
                            }
                            Spacer()
                        }

                        if let frame {
                            HStack(spacing: 24) {
                                InfoPill(
                                    icon: "location.fill",
                                    label: String(format: "%.5f, %.5f", frame.latitude, frame.longitude)
                                )
                                InfoPill(
                                    icon: "scope",
                                    label: String(format: "±%.0fm", frame.horizontalAccuracy)
                                )
                            }

                            InfoPill(
                                icon: "clock.fill",
                                label: frame.timestamp.formatted(date: .abbreviated, time: .standard)
                            )
                        }
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView(
                        "Detection Not Found",
                        systemImage: "questionmark.circle",
                        description: Text("This detection may have been evicted from memory.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.obsidian)
            .navigationTitle("Detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.spatialCyan)
                }
            }
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.voidGray)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.dimLabel)
                    Text("No image captured")
                        .font(.system(size: 13))
                        .foregroundStyle(.dimLabel)
                }
            }
    }
}

private struct InfoPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.spatialCyan)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.dimLabel)
        }
    }
}
