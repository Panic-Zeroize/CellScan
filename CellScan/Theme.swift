import SwiftUI

/// Central color + style tokens lifted from the CellScan design mock.
enum Theme {
    // Backgrounds
    static let bg = Color(hex: 0x0B0D10)
    static let bgElevated = Color(hex: 0x14171C)
    static let bgTile = Color(hex: 0x13161B)
    static let bgChip = Color(hex: 0x15181D)

    // Text
    static let text = Color(hex: 0xF2F4F6)
    static let textBright = Color(hex: 0xE8EBED)
    static let textDim = Color(hex: 0x717982)
    static let textFaint = Color(hex: 0x5C6670)

    // Accent
    static let accent = Color(hex: 0x6E6CFF)
    static let accentDeep = Color(hex: 0x5A57E8)
    static let danger = Color(hex: 0xFF453A)
    static let dangerSoft = Color(hex: 0xF4707E)
    static let success = Color(hex: 0x34D399)

    // Hairline border used on cards
    static let hairline = Color.white.opacity(0.07)

    static let mono = Font.system(.body, design: .monospaced)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

/// A rounded dark "card" container matching the mock.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 15
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 15, radius: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }

    /// Small uppercase section header ("RECENT", "METRICS", ...).
    func sectionHeader() -> some View {
        self
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(Theme.textFaint)
    }
}
