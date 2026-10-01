import SwiftUI
import AppKit

// Property-wrapper aliases. On the macOS 27 SDK `@State` & friends are macros whose plugin ships only
// with full Xcode; going through a typealias uses the plain property wrapper so Command Line Tools suffice.
typealias VState = SwiftUI.State
typealias VNamespace = SwiftUI.Namespace
typealias VFocusState = SwiftUI.FocusState

// MARK: - Dynamic colors

private func dyn(_ dark: NSColor, _ light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}
private func g(_ w: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(white: w, alpha: a) }

enum BD {
    static let bg        = dyn(g(0.035), g(0.965))
    static let bgRaised  = dyn(g(0.075), g(1.0))
    static let surface   = dyn(g(1, 0.045), g(0, 0.035))
    static let surfaceHi = dyn(g(1, 0.085), g(0, 0.06))
    static let stroke    = dyn(g(1, 0.09), g(0, 0.09))
    static let strokeHi  = dyn(g(1, 0.18), g(0, 0.16))
    static let text      = dyn(g(0.97), g(0.07))
    static let text2     = dyn(g(0.66), g(0.38))
    static let text3     = dyn(g(0.42), g(0.58))
    static let inverse   = dyn(g(0.04), g(0.98))
    static let mono      = dyn(g(0.97), g(0.07))

    static let green  = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let amber  = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let red    = Color(red: 0.98, green: 0.38, blue: 0.38)
    static let blue   = Color(red: 0.40, green: 0.62, blue: 1.00)
    static let violet = Color(red: 0.68, green: 0.55, blue: 1.00)
    static let teal   = Color(red: 0.35, green: 0.82, blue: 0.85)

    static let r1: CGFloat = 8, r2: CGFloat = 12, r3: CGFloat = 18, r4: CGFloat = 24

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
    static let soft   = Animation.easeInOut(duration: 0.22)
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case mono, blue, violet, green, amber, rose
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .mono: return BD.mono
        case .blue: return BD.blue
        case .violet: return BD.violet
        case .green: return BD.green
        case .amber: return BD.amber
        case .rose: return Color(red: 1.0, green: 0.45, blue: 0.62)
        }
    }
    var label: String { rawValue == "mono" ? "Monochrome" : rawValue.capitalized }
    /// Foreground to use on top of a filled accent.
    var onColor: Color { self == .mono ? BD.inverse : .white }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .dark ? .dark : self == .light ? .light : nil }
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }
}

enum Density: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var pad: CGFloat { self == .compact ? 10 : 16 }
}

/// UI preferences read throughout the views.
final class UIPrefs: ObservableObject {
    @AppStorage("ui.theme") var theme: ThemeChoice = .dark { didSet { apply(); objectWillChange.send() } }
    @AppStorage("ui.accent") var accent: AccentChoice = .mono { didSet { objectWillChange.send() } }
    @AppStorage("ui.glass") var glass: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage("ui.ambient") var ambient: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage("ui.motion") var motion: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage("ui.density") var density: Density = .comfortable { didSet { objectWillChange.send() } }
    @AppStorage("ui.sidebarCollapsed") var sidebarCollapsed: Bool = false { didSet { objectWillChange.send() } }
    @AppStorage("ui.sandboxLayout") var sandboxLayout: String = "grid" { didSet { objectWillChange.send() } }
    @AppStorage("ui.menuBar") var showMenuBar: Bool = true { didSet { objectWillChange.send() } }

    static let shared = UIPrefs()
    func apply() { NSApp?.appearance = theme.nsAppearance }
    var anim: Animation? { motion ? BD.spring : nil }
}

// MARK: - Glass

struct GlassCard: ViewModifier {
    @EnvironmentObject var prefs: UIPrefs
    var radius: CGFloat = BD.r3
    var padding: CGFloat? = nil
    var interactive = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(padding ?? prefs.density.pad)
        if prefs.glass {
            if #available(macOS 26.0, *) {
                padded
                    .glassEffect(glassValue, in: shape)
            } else {
                padded
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.strokeBorder(BD.stroke, lineWidth: 1))
            }
        } else {
            padded
                .background(BD.bgRaised, in: shape)
                .overlay(shape.strokeBorder(BD.stroke, lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    var glassValue: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.18)) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Flat translucent panel (lighter than glass) used for nested blocks inside cards.
struct Panel: ViewModifier {
    var radius: CGFloat = BD.r2
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(BD.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = BD.r3, padding: CGFloat? = nil, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassCard(radius: radius, padding: padding, interactive: interactive, tint: tint))
    }
    func panel(radius: CGFloat = BD.r2, padding: CGFloat = 12) -> some View {
        modifier(Panel(radius: radius, padding: padding))
    }
    /// Groups sibling glass shapes so they blend (macOS 26+).
    @ViewBuilder func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: spacing) { self } } else { self }
    }
    func hoverLift(_ amount: CGFloat = 1.015) -> some View { modifier(HoverLift(amount: amount)) }
    func appear(delay: Double = 0) -> some View { modifier(AppearIn(delay: delay)) }
}

struct HoverLift: ViewModifier {
    @EnvironmentObject var prefs: UIPrefs
    var amount: CGFloat
    @VState private var hover = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hover && prefs.motion ? amount : 1)
            .shadow(color: .black.opacity(hover ? 0.28 : 0), radius: hover ? 18 : 0, y: hover ? 8 : 0)
            .animation(BD.snappy, value: hover)
            .onHover { hover = $0 }
    }
}

struct AppearIn: ViewModifier {
    @EnvironmentObject var prefs: UIPrefs
    var delay: Double
    @VState private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !prefs.motion ? 0 : 10)
            .onAppear {
                if prefs.motion { withAnimation(BD.spring.delay(delay)) { shown = true } } else { shown = true }
            }
    }
}

// MARK: - Ambient background

struct AmbientBackground: View {
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.colorScheme) var scheme

    var body: some View {
        ZStack {
            BD.bg
            if prefs.ambient {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: !prefs.motion)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let blobs: [(Double, Double, Double, Double)] = [
                            (0.18, 0.22, 0.42, 0.00), (0.82, 0.18, 0.36, 1.7),
                            (0.70, 0.86, 0.46, 3.1), (0.22, 0.78, 0.30, 4.4)]
                        for (i, b) in blobs.enumerated() {
                            let x = (b.0 + 0.06 * sin(t / 9 + b.3)) * size.width
                            let y = (b.1 + 0.06 * cos(t / 11 + b.3 * 1.3)) * size.height
                            let r = b.2 * max(size.width, size.height)
                            let base: Double = scheme == .dark ? (i % 2 == 0 ? 0.075 : 0.05) : (i % 2 == 0 ? 0.05 : 0.035)
                            let col = scheme == .dark ? Color.white.opacity(base) : Color.black.opacity(base)
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .radialGradient(Gradient(colors: [col, .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                        }
                    }
                }
                GridPattern().opacity(scheme == .dark ? 0.035 : 0.05)
            }
        }
        .ignoresSafeArea()
    }
}

struct GridPattern: View {
    var spacing: CGFloat = 28
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            ctx.stroke(p, with: .color(BD.text), lineWidth: 0.5)
        }
        .mask(RadialGradient(colors: [.black, .clear], center: .top, startRadius: 0, endRadius: 900))
        .allowsHitTesting(false)
    }
}

// MARK: - Typography helpers

extension Font {
    static let bdTitle = Font.system(size: 26, weight: .semibold, design: .default)
    static let bdH2 = Font.system(size: 17, weight: .semibold)
    static let bdH3 = Font.system(size: 13, weight: .semibold)
    static let bdBody = Font.system(size: 13)
    static let bdSmall = Font.system(size: 11.5)
    static let bdMono = Font.system(size: 12, design: .monospaced)
    static let bdMonoSmall = Font.system(size: 11, design: .monospaced)
    static let bdStat = Font.system(size: 30, weight: .semibold, design: .rounded)
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(BD.text3)
    }
}
