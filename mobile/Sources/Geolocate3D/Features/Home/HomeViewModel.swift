import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var searchText: String = ""

    func deleteRoom(_ room: RoomRecord, from roomStore: RoomStore) {
        try? roomStore.deleteRoom(room)
    }
}
