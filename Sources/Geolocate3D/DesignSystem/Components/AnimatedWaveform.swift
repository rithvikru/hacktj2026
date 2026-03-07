// DesignSystem/Components/AnimatedWaveform.swift
import SwiftUI

struct AnimatedWaveform: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 3
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(Color.spatialCyan)
                        .frame(width: 4, height: 10 + CGFloat(sin(phase + Double(i))) * 8)
                }
            }
        }
    }
}
