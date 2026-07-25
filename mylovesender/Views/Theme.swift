import SwiftUI

enum LoveTheme {
    static let accent = Color(red: 168 / 255, green: 61 / 255, blue: 1)
    static let lavender = Color(red: 217 / 255, green: 172 / 255, blue: 1)
    static let cream = Color(red: 250 / 255, green: 244 / 255, blue: 231 / 255)
    static let ink = Color(red: 17 / 255, green: 13 / 255, blue: 21 / 255)

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? ink : cream
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 28 / 255, green: 22 / 255, blue: 34 / 255) : .white.opacity(0.9)
    }
}

struct LoveCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(LoveTheme.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LoveTheme.lavender.opacity(colorScheme == .dark ? 0.25 : 0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 14, y: 8)
    }
}

struct StatusBadge: View {
    let status: LetterStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LoveTheme.accent.opacity(0.16), in: Capsule())
            .foregroundStyle(LoveTheme.accent)
            .accessibilityLabel("Status: \(status.title)")
    }
}

struct ConnectionBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ConnectionState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state == .connected ? "heart.circle.fill" : "heart.circle")
                .foregroundStyle(state == .connected ? LoveTheme.accent : .secondary)
                .scaleEffect(!reduceMotion && pulse && state == .connected ? 1.08 : 1)
            Text(state.title)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
    }
}
