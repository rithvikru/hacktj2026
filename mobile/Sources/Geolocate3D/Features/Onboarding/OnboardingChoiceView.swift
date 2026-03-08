import SwiftUI

struct OnboardingChoiceView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredMode") private var preferredMode = ""
    @State private var selectedMode: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("Uncover")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("How do you want to find things?")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.bottom, 48)

            VStack(spacing: 16) {
                ModeCard(
                    title: "Inside",
                    subtitle: "Scan a room, find your things",
                    isSelected: selectedMode == "inside"
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMode = "inside"
                    }
                    completeOnboarding(mode: "inside")
                }

                ModeCard(
                    title: "Outside",
                    subtitle: "Explore with glasses + maps",
                    isSelected: selectedMode == "outside"
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMode = "outside"
                    }
                    completeOnboarding(mode: "outside")
                }
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.spaceBlack)
    }

    private func completeOnboarding(mode: String) {
        preferredMode = mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                hasCompletedOnboarding = true
            }
        }
    }
}

private struct ModeCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.zinc900)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.spatialCyan.opacity(0.6) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
    }
}
