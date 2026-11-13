import SwiftUI

/// Light, airy surfaces: white cards on a near-white page, one ink colour for content,
/// a starry pastel glow at the top of the main screens. Light mode only for now.
enum Theme {
    static let bg       = Color(hex: 0xFAFAFC)
    static let card     = Color.white
    static let fill     = Color(hex: 0x17161F).opacity(0.05)   // chips, small pills, month buttons
    static let line     = Color(hex: 0xEFEEF3)
    static let ink      = Color(hex: 0x17161F)
    static let muted    = Color(hex: 0x6B6880)
    static let faint    = Color(hex: 0x8A879B)                  // currency symbol, paise, disabled
    static let accent   = Color(hex: 0x4A57C9)                  // links and the selected toggle only
    static let selected = Color(hex: 0x7B6CF6)                  // a picked bar in the home chart
    static let positive = Color(hex: 0x15803D)

    // The starry glow
    static let glowBlue  = Color(hex: 0x8FA2F7)
    static let glowPink  = Color(hex: 0xF7C6DA)
    static let glowPeach = Color(hex: 0xFFE2C4)
    static let starGold  = Color(hex: 0xE8C76A)

    static let radius: CGFloat = 28
    static let shadow = Color(red: 40 / 255, green: 40 / 255, blue: 90 / 255)

    /// Elegant serif (New York) for a few headings: the "Penny" title and Penny's moments.
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Soft periwinkle, pink and peach glow with a scatter of stars, pinned to the top of the screen.
/// The stars twinkle and drift a few points; with Reduce Motion they hold still.
struct StarryTop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private struct Star {
        let x: CGFloat, y: CGFloat, size: CGFloat
        let color: Color
        let phase: Double, speed: Double
    }

    private static let stars: [Star] = [
        Star(x: 44, y: 26, size: 9, color: .white, phase: 0.0, speed: 1.1),
        Star(x: 196, y: 40, size: 7, color: Theme.starGold, phase: 1.3, speed: 0.8),
        Star(x: 300, y: 112, size: 6, color: .white, phase: 2.1, speed: 1.3),
        Star(x: 262, y: 224, size: 8, color: Theme.glowBlue, phase: 0.7, speed: 0.9),
        Star(x: 22, y: 250, size: 6, color: Theme.starGold, phase: 2.8, speed: 1.0),
        Star(x: 120, y: 96, size: 5, color: .white, phase: 1.9, speed: 1.4),
        Star(x: 352, y: 46, size: 8, color: .white, phase: 0.4, speed: 0.7),
        Star(x: 88, y: 168, size: 5, color: Theme.glowBlue, phase: 3.3, speed: 1.2),
        Star(x: 236, y: 132, size: 4, color: Theme.starGold, phase: 2.5, speed: 1.6),
        Star(x: 330, y: 196, size: 5, color: Theme.starGold, phase: 1.1, speed: 0.95),
        Star(x: 160, y: 210, size: 4, color: .white, phase: 3.9, speed: 1.15),
        Star(x: 12, y: 120, size: 5, color: .white, phase: 0.9, speed: 1.25),
        Star(x: 270, y: 14, size: 5, color: Theme.glowBlue, phase: 2.2, speed: 0.85),
        Star(x: 372, y: 140, size: 4, color: .white, phase: 3.0, speed: 1.35),
        Star(x: 60, y: 300, size: 4, color: Theme.glowBlue, phase: 1.6, speed: 1.05),
        Star(x: 210, y: 290, size: 5, color: .white, phase: 0.2, speed: 0.75),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The glow never changes: render it once into an image (drawingGroup) instead of
            // re-blurring it every time a star moves. Tall enough that the blur fades out inside it.
            ZStack(alignment: .topLeading) {
                Circle().fill(Theme.glowBlue).frame(width: 360, height: 360)
                    .blur(radius: 90).opacity(0.55).offset(x: -90, y: -130)
                Ellipse().fill(Theme.glowPink).frame(width: 300, height: 280)
                    .blur(radius: 90).opacity(0.5).offset(x: 200, y: -70)
                Ellipse().fill(Theme.glowPeach).frame(width: 220, height: 160)
                    .blur(radius: 80).opacity(0.4).offset(x: 120, y: 140)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 620, alignment: .top)
            .drawingGroup()
            // All stars drawn in one pass, 15 times a second (the twinkle is slow), and only while
            // the app is on screen. Behind frosted glass every redraw also re-blurs the glass.
            TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || scenePhase != .active)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { gc, _ in
                    for (i, s) in Self.stars.enumerated() {
                        guard let symbol = gc.resolveSymbol(id: i) else { continue }
                        let wave = sin(t * s.speed + s.phase)                 // -1…1
                        var g = gc
                        g.opacity = 0.35 + 0.65 * (0.5 + 0.5 * wave)          // never fully off
                        g.translateBy(x: s.x + s.size / 2 + 3 * sin(t * 0.25 + s.phase),
                                      y: s.y + s.size / 2 + 2.5 * cos(t * 0.2 + s.phase * 1.3))
                        let scale = 0.85 + 0.2 * (0.5 + 0.5 * wave)
                        g.scaleBy(x: scale, y: scale)
                        g.draw(symbol, at: .zero)
                    }
                } symbols: {
                    ForEach(Self.stars.indices, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: Self.stars[i].size))
                            .foregroundStyle(Self.stars[i].color)
                            .tag(i)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 340, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The same soft periwinkle and pink glow, tucked into the bottom-right corner of a page.
struct CornerGlow: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Ellipse().fill(Theme.glowBlue).frame(width: 320, height: 300)
                .blur(radius: 90).opacity(0.42).offset(x: 120, y: 110)
            Ellipse().fill(Theme.glowPink).frame(width: 260, height: 240)
                .blur(radius: 90).opacity(0.38).offset(x: -30, y: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A softer glow (no stars) for the top of drawers.
struct DrawerGlow: View {
    var body: some View {
        ZStack(alignment: .top) {
            Ellipse().fill(Theme.glowBlue.opacity(0.32)).frame(width: 300, height: 220)
                .blur(radius: 60).offset(x: -90, y: -90)
            Ellipse().fill(Theme.glowPink.opacity(0.45)).frame(width: 240, height: 180)
                .blur(radius: 60).offset(x: 120, y: -50)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: 260, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A horizontal dashed line, used under editable text.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Selectable rounded chip: dark when chosen, soft grey otherwise, dashed for "+ New".
struct ChoiceChip: View {
    let title: String
    var selected = false
    var dashed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.card : (dashed ? Theme.muted : Theme.ink))
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background {
                    if dashed {
                        Capsule().strokeBorder(Color(hex: 0xCFCDD8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    } else {
                        Capsule().fill(selected ? Theme.ink : Theme.fill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Top of a pushed screen: glass back button, serif title, optional controls on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(CircleButtonStyle(size: 40))
                .accessibilityLabel("Back")
            (Text(title) + Text(subtitle.map { " \($0)" } ?? "").foregroundStyle(Theme.faint))
                .font(Theme.serif(32)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// Near-white page with the starry glow at the top, no navigation bar (screens use PageHeader).
    func starryPage() -> some View {
        self
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Theme.bg
                    CornerGlow()
                    StarryTop()
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The shadow belongs to the card's shape, not its contents, so an animation inside
            // (e.g. sleeping Penny) doesn't force the shadow to be redrawn every frame.
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
            }
    }
}

/// Frosted glass: translucent white with a thin bright edge, so the glow behind shows through.
struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                // Shadow from a solid copy of the shape with its inside cut away: it looks like the
                // card's own shadow, but doesn't depend on what's behind or inside the glass, so it
                // isn't redrawn whenever the stars twinkle.
                shape.fill(Color.white)
                    .shadow(color: Theme.shadow.opacity(0.07), radius: 16, y: 8)
                    .mask {
                        Rectangle().padding(-60)
                            .overlay(shape.fill(Color.black).blendMode(.destinationOut))
                            .compositingGroup()
                    }
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.45))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
    }
}

/// Glass that dissolves into the page toward the top-right corner and firms up toward the bottom-left.
struct FadingGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    private let fade = LinearGradient(colors: [.clear, .white.opacity(0.6), .white], startPoint: .topTrailing, endPoint: .bottomLeading)

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(0.5))
                }
                .mask(fade)
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.clear, .white.opacity(0.9)], startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 1))
            .shadow(color: Theme.shadow.opacity(0.05), radius: 18, x: -6, y: 10)
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S) -> some View { modifier(GlassModifier(shape: shape)) }

    /// The month total card: glass that fades into the background from the top-right.
    func fadingGlassCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FadingGlassModifier(shape: RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous)))
    }

    /// A glass card with the standard padding and corner radius.
    func glassCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardModifier(padding: padding)) }

    /// App background for Forms and scroll views.
    func pennyBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}

/// Small grey label above a card, e.g. "Today        ₹858".
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
            .background(primary ? Theme.ink : Theme.fill, in: Capsule())
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
    var size: CGFloat = 44
    /// nil = frosted glass (header buttons over the glow)
    var background: Color? = nil
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background { if let background { Circle().fill(background) } }
            .modifier(OptionalGlass(on: background == nil))
            .opacity(enabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct OptionalGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.glass(Circle()) } else { content }
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
            .font(.system(size: big ? size * 0.5 : size, weight: big ? .regular : weight))
            .baselineOffset(big ? size * 0.32 : 0)
            .foregroundStyle(big ? Theme.faint : color)
        return (symbol
            + Text(big ? "\u{2009}" : "")
            + Text(p.whole).foregroundStyle(color)
            + Text(p.fraction).foregroundStyle(Theme.faint))
            .font(.system(size: size, weight: weight))
            .tracking(big ? -size * 0.045 : -0.2)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(big ? 0.5 : 1)
            .fixedSize(horizontal: !big, vertical: false)
    }
}
