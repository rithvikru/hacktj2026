// DesignSystem/Components/FloatingQueryBar.swift
import SwiftUI

struct FloatingQueryBar: View {
    var onSubmit: (String) -> Void
    @State private var query = ""
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isRecording.toggle()
                }
            } label: {
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isRecording ? .white : .dimLabel)
                    .frame(width: 40, height: 40)
                    .background(isRecording ? Color.spatialCyan.opacity(0.8) : Color.white.opacity(0.06))
                    .clipShape(Circle())
            }

            if isRecording {
                AnimatedWaveform()
                    .frame(height: 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                TextField("Find something...", text: $query)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .tint(.spatialCyan)
                    .transition(.opacity)
                    .onSubmit {
                        onSubmit(query)
                        query = ""
                    }
            }
            Spacer(minLength: 0)

            if !query.isEmpty && !isRecording {
                Button {
                    onSubmit(query)
                    query = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.spatialCyan)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.elevatedSurface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .padding(.horizontal, 20)
    }
}
