import SwiftUI
import SwiftData

struct ScanCompletionSheet: View {
    let roomID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.confirmGreen)

                Text("Room Captured")
                    .font(SpatialFont.title)
                    .foregroundStyle(.white)

                Text("Name your space to save it.")
                    .font(SpatialFont.subheadline)
                    .foregroundStyle(.dimLabel)

                TextField("Living Room", text: $roomName)
                    .font(SpatialFont.body)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 0.5)
                    )

                Button {
                    saveRoom()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(SpatialButtonStyle())
                .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                Spacer()
            }
            .padding(24)
            .background(Color.obsidian)
            .navigationTitle("Save Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.dimLabel)
                }
            }
        }
    }

    private func saveRoom() {
        let trimmed = roomName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true

        let room = RoomRecord(id: roomID, name: trimmed)
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let roomDir = docsDir.appendingPathComponent("rooms/\(roomID.uuidString)")
        let usdzPath = roomDir.appendingPathComponent("room.usdz").path
        if FileManager.default.fileExists(atPath: usdzPath) {
            room.roomUSDZPath = usdzPath
        }
        room.reconstructionStatusRaw = ReconstructionStatus.complete.rawValue

        modelContext.insert(room)
        try? modelContext.save()
        dismiss()
    }
}
