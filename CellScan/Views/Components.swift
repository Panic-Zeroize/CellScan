import SwiftUI

/// A small labeled metric tile used across Recording / Summary / detail.
struct StatTile: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textFaint)
            Text(value)
                .font(.system(size: 22, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(Theme.bgTile)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

/// Live throughput sparkline — bar color + height encode measured download speed.
/// Samples with no measurement yet render as a short neutral bar.
struct Sparkline: View {
    var downloads: [Double?]

    private let neutral = Color(hex: 0x3A4048)

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(downloads.enumerated()), id: \.offset) { _, d in
                bar(for: d)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .animation(.easeOut(duration: 0.2), value: downloads.count)
    }

    @ViewBuilder private func bar(for down: Double?) -> some View {
        if let down {
            let tier = CoverageTier.from(downMbps: down)
            RoundedRectangle(cornerRadius: 2)
                .fill(tier.color)
                .frame(width: 5, height: max(4, CGFloat(tier.rank + 1) / 5 * 34))
                .shadow(color: tier.color.opacity(0.5), radius: 3)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(neutral)
                .frame(width: 5, height: 5)
        }
    }
}

/// Horizontal stacked coverage bar from a list of (color, fraction) segments.
struct CoverageBar: View {
    var segments: [(color: Color, fraction: Double)]
    var height: CGFloat = 11
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, geo.size.width * seg.fraction))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }
}

/// The colored RAT badge shown on the recording screen and map detail.
struct SignalBadge: View {
    var rat: RAT
    var sub: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rat.color)
                .frame(width: 9, height: 9)
                .shadow(color: rat.color, radius: 4)
            Text(rat.label)
                .font(.system(size: 17, weight: .heavy))
            if let sub {
                Text(sub)
                    .font(.system(size: 12))
                    .opacity(0.6)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 17)
        .background(rat.color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(rat.color.opacity(0.5), lineWidth: 1))
        .foregroundStyle(rat.color)
    }
}

/// A colored dot + label row (used in legends / breakdowns).
struct DotLabel: View {
    var color: Color
    var text: String
    var size: CGFloat = 10
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(text)
        }
    }
}

/// Rounded primary/secondary action button matching the mock.
struct BigButton: View {
    enum Kind { case primary, danger, secondary }
    var title: String
    var kind: Kind = .primary
    var systemIcon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let systemIcon { Image(systemName: systemIcon) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(border)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .danger:
            LinearGradient(colors: [Theme.danger, Color(hex: 0xE0392F)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary:
            Theme.bgChip
        }
    }
    private var foreground: Color { kind == .secondary ? Color(hex: 0xD7DBDF) : .white }
    @ViewBuilder private var border: some View {
        if kind == .secondary {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}
