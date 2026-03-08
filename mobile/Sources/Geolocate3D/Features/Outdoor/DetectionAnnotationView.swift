import SwiftUI

struct DetectionAnnotationView: View {
    let detection: OutdoorDetection

    private var confidenceColor: Color {
        detection.confidence >= 0.7 ? .spatialCyan : .warningAmber
    }

    private var icon: String {
        switch detection.label.lowercased() {
        case let l where l.contains("car"): return "car.fill"
        case let l where l.contains("bag"), let l where l.contains("backpack"): return "bag.fill"
        case let l where l.contains("bicycle"), let l where l.contains("bike"): return "bicycle"
        case let l where l.contains("dog"): return "dog.fill"
        case let l where l.contains("phone"): return "iphone"
        case let l where l.contains("key"): return "key.fill"
        case let l where l.contains("umbrella"): return "umbrella.fill"
        case let l where l.contains("bench"): return "chair.fill"
        case let l where l.contains("sign"): return "signpost.right.fill"
        default: return "mappin.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(detection.label.capitalized)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(confidenceColor.opacity(0.85))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: confidenceColor.opacity(0.4), radius: 8, y: 4)

            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(confidenceColor.opacity(0.85))
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
    }
}
