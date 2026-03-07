import SwiftUI
import SwiftData

@Observable
@MainActor
final class HomeViewModel {
    var searchText: String = ""

    func deleteRoom(_ room: RoomRecord, from context: ModelContext) {
        context.delete(room)
        try? context.save()
    }
}
