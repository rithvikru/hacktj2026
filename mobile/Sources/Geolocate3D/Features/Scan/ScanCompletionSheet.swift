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
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.confirmGreen)

                    Text("Room Captured")
                        .font(SpatialFont.title2)
                        .foregroundStyle(.white)

                    Text("Give your space a name to save it.")
                        .font(SpatialFont.subheadline)
                        .foregroundStyle(.dimLabel)
                }

                TextField("Living Room", text: $roomName)
                    .font(SpatialFont.body)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                Button {
                    saveRoom()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(SpatialButtonStyle())
                .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                Spacer()
            }
            .padding(24)
            .background(Color.spaceBlack)
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
