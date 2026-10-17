import SwiftUI

extension Color {
    /// Build a color from "#RRGGBB" (or "RRGGBB"). Returns nil on bad input.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Aurora — MacStrike's dark theme: blue→purple accents over deep navy.
enum Theme {
    static let bg         = Color(hex: "#0B0D14")!
    static let bgRaised   = Color(hex: "#10131C")!
    static let card       = Color.white.opacity(0.04)
    static let stroke     = Color.white.opacity(0.07)
    static let textPrimary   = Color(hex: "#E8ECF5")!
    static let textSecondary = Color(hex: "#8893AB")!

    static let accentFrom = Color(hex: "#5B8CFF")!
    static let accentTo   = Color(hex: "#7A5CFF")!
    static let accent     = accentFrom
    static let ok         = Color(hex: "#6EE7A8")!
    static let warn       = Color(hex: "#FFB065")!

    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 10

    static let accentGradient = LinearGradient(
        colors: [accentFrom, accentTo], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// A card gradient from a `Game`'s hex pair, falling back to the accent.
    static func gradient(from: String, to: String) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: from) ?? accentFrom, Color(hex: to) ?? accentTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The app background: a subtle vertical wash, not a flat fill.
    static let backgroundWash = LinearGradient(
        colors: [bgRaised, bg], startPoint: .top, endPoint: .bottom)
}

/// Standard raised panel: translucent fill, hairline stroke, rounded corners.
struct AuroraCard: ViewModifier {
    var radius: CGFloat = Theme.radius
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func auroraCard(radius: CGFloat = Theme.radius) -> some View {
        modifier(AuroraCard(radius: radius))
    }
}

/// The primary call-to-action: gradient fill, white text, springy press.
struct AuroraButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Theme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
