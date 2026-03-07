// DesignSystem/Components/FloatingQueryBar.swift
import SwiftUI

struct FloatingQueryBar: View {
    var onSubmit: (String) -> Void
    @State private var query = ""
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRecording.toggle()
                }
            } label: {
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isRecording ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(isRecording ? Color.spatialCyan : .white.opacity(0.1))
                    .clipShape(Circle())
            }

            if isRecording {
                AnimatedWaveform()
                    .frame(height: 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TextField("Find objects...", text: $query)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.spatialCyan)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .onSubmit {
                        onSubmit(query)
                        query = ""
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .padding(.horizontal, 24)
    }
}
