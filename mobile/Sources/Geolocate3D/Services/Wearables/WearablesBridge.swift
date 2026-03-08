import Foundation

@MainActor
protocol WearablesBridge: AnyObject {
    var registrationState: WearableRegistrationState { get }
    var streamState: WearableStreamState { get }

    func configure() throws
    func beginRegistration() async throws
    func handleOpenURL(_ url: URL) async throws -> Bool
    func startStreaming(
        onFrame: @escaping @Sendable (WearableCapturedFrame) -> Void,
        onStateChange: @escaping @Sendable (WearableStreamState) -> Void
    ) async throws
    func stopStreaming() async
}
