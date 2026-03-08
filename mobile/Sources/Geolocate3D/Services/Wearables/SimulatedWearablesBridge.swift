import Foundation
import UIKit

@MainActor
final class SimulatedWearablesBridge: WearablesBridge {
    private(set) var registrationState: WearableRegistrationState = .unconfigured
    private(set) var streamState: WearableStreamState = .idle

    private var streamTask: Task<Void, Never>?
    private var frameIndex = 0
    private let places = ["Kitchen", "Living Room", "Bedroom", "Hallway", "Desk"]
    private let labels = ["wallet", "keys", "charger", "glasses", "remote"]

    func configure() throws {
        registrationState = .registrationRequired
    }

    func beginRegistration() async throws {
        registrationState = .registering
        registrationState = .registered
    }

    func handleOpenURL(_ url: URL) async throws -> Bool {
        registrationState = .registered
        return true
    }

    func startStreaming(
        onFrame: @escaping @Sendable (WearableCapturedFrame) -> Void,
        onStateChange: @escaping @Sendable (WearableStreamState) -> Void
    ) async throws {
        guard case .registered = registrationState else {
            let err = WearablesBridgeError.registrationFailed("Simulated bridge not registered")
            registrationState = .failed(err.localizedDescription)
            throw err
        }

        streamTask?.cancel()
        frameIndex = 0
        streamState = .connecting
        onStateChange(.connecting)

        streamState = .streaming
        onStateChange(.streaming)

        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, let self else { return }
                await self.emitFrame(onFrame: onFrame)
            }
        }
    }

    private func emitFrame(onFrame: @Sendable (WearableCapturedFrame) -> Void) {
        frameIndex += 1
        let place = places[frameIndex % places.count]
        let label = labels[frameIndex % labels.count]
        let image = makeFrameImage(index: frameIndex, place: place, label: label)
        let observed = WearableObservedObjectPayload(
            label: label,
            confidence: 0.65 + Double((frameIndex % 20)) / 100.0
        )
        let frame = WearableCapturedFrame(
            image: image,
            placeHint: place,
            observedObjects: [observed],
            sampleReason: "simulated_stream",
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        onFrame(frame)
    }

    func stopStreaming() async {
        streamTask?.cancel()
        streamTask = nil
        streamState = .stopped
    }

    private func makeFrameImage(index: Int, place: String, label: String) -> UIImage {
        let size = CGSize(width: 720, height: 540)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let colors: [UIColor] = [
                UIColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1.0),
                UIColor(red: 0.14, green: 0.29, blue: 0.42, alpha: 1.0),
                UIColor(red: 0.87, green: 0.49, blue: 0.19, alpha: 1.0),
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let cgColors = colors.map(\.cgColor) as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations)!
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let pill = UIBezierPath(
                roundedRect: CGRect(x: 32, y: 28, width: 240, height: 42),
                cornerRadius: 20
            )
            UIColor.white.withAlphaComponent(0.14).setFill()
            pill.fill()

            let title = "Simulated Meta Frame"
            let subtitle = "\(place) • \(label) • #\(index)"
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let textStyle = NSMutableParagraphStyle()
            textStyle.alignment = .left

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: textStyle,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: textStyle,
            ]
            let timestampAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                .paragraphStyle: textStyle,
            ]

            title.draw(in: CGRect(x: 36, y: 104, width: bounds.width - 72, height: 40), withAttributes: titleAttributes)
            subtitle.draw(in: CGRect(x: 36, y: 150, width: bounds.width - 72, height: 30), withAttributes: subtitleAttributes)
            timestamp.draw(in: CGRect(x: 36, y: 186, width: bounds.width - 72, height: 24), withAttributes: timestampAttributes)

            let focusRect = CGRect(x: 178, y: 236, width: 360, height: 170)
            let focusPath = UIBezierPath(roundedRect: focusRect, cornerRadius: 28)
            UIColor.white.withAlphaComponent(0.18).setStroke()
            focusPath.lineWidth = 4
            focusPath.stroke()
        }
    }
}
