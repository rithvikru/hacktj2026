// DesignSystem/Components/AnimatedWaveform.swift
import SwiftUI

struct AnimatedWaveform: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 2.5
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(Color.spatialCyan.opacity(0.7))
                        .frame(width: 3, height: 8 + CGFloat(sin(phase + Double(i) * 0.8)) * 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: phase)
                }
            }
        }
    }
}
