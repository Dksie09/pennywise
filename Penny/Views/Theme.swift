import SwiftUI

/// Soft neutral surfaces, one accent, big numbers. Every colour adapts to dark mode.
enum Theme {
    static let bg       = Color(light: 0xEEEEF0, dark: 0x0B0B0C)
    static let card     = Color(light: 0xFFFFFF, dark: 0x1A1A1D)
    static let fill     = Color(light: 0xF2F2F4, dark: 0x26262A)   // chips, light pills, circle buttons
    static let line     = Color(light: 0xE6E6EA, dark: 0x2C2C31)
    static let ink      = Color(light: 0x111113, dark: 0xF4F4F5)
    static let muted    = Color(light: 0x8A8A91, dark: 0x8E8E96)
    static let accent   = Color(light: 0x4F46E5, dark: 0x8F88FF)
    static let positive = Color(light: 0x15803D, dark: 0x4ADE80)

    static let radius: CGFloat = 28
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardModifier(padding: padding)) }

    /// Grey app background for Forms and scroll views.
    func pennyBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}

/// Small grey label above a card, e.g. "THU, 6 NOV".
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            trailing
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .foregroundStyle(primary ? Theme.card : Theme.ink)
            .background(primary ? Theme.ink : Theme.card, in: Capsule())
            .shadow(color: .black.opacity(primary ? 0 : 0.04), radius: 10, y: 4)
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillLight: PillButtonStyle { PillButtonStyle(primary: false) }
}

/// Compact grey pill for secondary links inside a card, e.g. "Breakdown".
struct SmallPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    var background: Color = Theme.card
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .opacity(enabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// A small rounded chip, e.g. "↘ ₹2,100 less than October".
struct Chip: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.ink

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.fill, in: Capsule())
    }
}

// MARK: - Money

/// "₹12,392.50" with the symbol and paise in grey, so the rupees read first.
struct AmountText: View {
    let value: Double
    var currency = "INR"
    var size: CGFloat = 17
    var weight: Font.Weight = .medium
    var sign = ""
    var color: Color = Theme.ink

    var body: some View {
        let p = Fmt.parts(Fmt.money(value, currency))
        let big = size > 28
        let symbol = Text(sign + p.symbol)
            .font(.system(size: big ? size * 0.55 : size, weight: weight))
            .baselineOffset(big ? size * 0.3 : 0)
            .foregroundStyle(big ? Theme.muted : color)
        return (symbol
            + Text(big ? "\u{2009}" : "")
            + Text(p.whole).foregroundStyle(color)
            + Text(p.fraction).foregroundStyle(Theme.muted))
            .font(.system(size: size, weight: weight))
            .tracking(big ? -size * 0.03 : 0)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(big ? 0.5 : 1)
            .fixedSize(horizontal: !big, vertical: false)
    }
}
