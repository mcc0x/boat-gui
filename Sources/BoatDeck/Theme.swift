import SwiftUI
import AppKit

// Property-wrapper aliases. On the macOS 27 SDK `@State` & friends are macros whose plugin ships only
// with full Xcode; going through a typealias uses the plain property wrapper so Command Line Tools suffice.
//
// `VState` is our own @State replacement backed by @StateObject: plain `SwiftUI.State` used through a typealias
// compiles on this SDK but its writes don't take effect without the macro expansion.
@propertyWrapper
struct VState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ v: Value) { value = v }
    }
    @StateObject private var box: Box

    init(wrappedValue: Value) { _box = StateObject(wrappedValue: Box(wrappedValue)) }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<Value> {
        let b = box
        return Binding(get: { b.value }, set: { b.value = $0 })
    }
}
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
    static let bg        = dyn(NSColor(srgbRed: 0.105, green: 0.12, blue: 0.135, alpha: 1), NSColor(srgbRed: 0.90, green: 0.915, blue: 0.91, alpha: 1))
    static let bgRaised  = dyn(NSColor(srgbRed: 0.15, green: 0.17, blue: 0.185, alpha: 1), NSColor(srgbRed: 0.955, green: 0.965, blue: 0.96, alpha: 1))
    static let surface   = dyn(g(1, 0.045), g(0, 0.035))
    static let surfaceHi = dyn(g(1, 0.085), g(0, 0.06))
    static let stroke    = dyn(g(1, 0.09), g(0, 0.09))
    static let strokeHi  = dyn(g(1, 0.18), g(0, 0.16))
    static let text      = dyn(g(0.92), g(0.12))
    static let text2     = dyn(g(0.74), g(0.32))
    static let text3     = dyn(g(0.61), g(0.43))
    static let inverse   = dyn(g(0.04), g(0.98))
    static let mono      = dyn(g(0.97), g(0.07))

    static let green  = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let amber  = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let red    = Color(red: 0.98, green: 0.38, blue: 0.38)
    static let blue   = dyn(NSColor(srgbRed: 0.28, green: 0.49, blue: 0.86, alpha: 1), NSColor(srgbRed: 0.18, green: 0.38, blue: 0.72, alpha: 1))
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
    @AppStorage("ui.theme") var theme: ThemeChoice = .dark { didSet { apply() } }
    @AppStorage("ui.accent") var accent: AccentChoice = .mono
    @AppStorage("ui.glass") var glass: Bool = true
    @AppStorage("ui.ambient") var ambient: Bool = true
    @AppStorage("ui.motion") var motion: Bool = true
    @AppStorage("ui.density") var density: Density = .comfortable
    @AppStorage("ui.sidebarCollapsed") var sidebarCollapsed: Bool = false
    @AppStorage("ui.sandboxLayout") var sandboxLayout: String = "list"
    @AppStorage("ui.menuBar") var showMenuBar: Bool = true

    static let shared = UIPrefs()
    func apply() { NSApp?.appearance = theme.nsAppearance }
    var anim: Animation? { motion ? BD.spring : nil }
}

// MARK: - Glass

struct GlassCard: ViewModifier {
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = BD.r3
    var padding: CGFloat? = nil
    var interactive = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(padding ?? prefs.density.pad)
        if prefs.glass && !reduceTransparency {
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
    /// Entrance animations only play within this window after navigation, so a view that gets rebuilt later
    /// (resize, data refresh) never blinks out and back in.
    static var allowUntil = Date().addingTimeInterval(1.5)
    static func pageOpened() { allowUntil = Date().addingTimeInterval(0.8) }

    @EnvironmentObject var prefs: UIPrefs
    var delay: Double
    @VState private var shown = Date() > AppearIn.allowUntil
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !prefs.motion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if prefs.motion && Date() <= AppearIn.allowUntil {
                    withAnimation(BD.spring.delay(delay)) { shown = true }
                } else { shown = true }
            }
    }
}

// MARK: - Ambient background

/// A stationary tint keeps the workspace calm and avoids continuous full-window redraws.
struct AmbientBackground: View {
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.colorScheme) var scheme

    var body: some View {
        ZStack {
            BD.bg
            if prefs.ambient {
                LinearGradient(colors: [
                    BD.teal.opacity(scheme == .dark ? 0.045 : 0.035),
                    .clear,
                    BD.blue.opacity(scheme == .dark ? 0.035 : 0.025)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Real behind-window vibrancy, rather than a translucent layer over an opaque canvas.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Typography helpers

extension Font {
    static let bdTitle = Font.system(size: 26, weight: .semibold, design: .default)
    static let bdH2 = Font.system(size: 17, weight: .semibold)
    static let bdH3 = Font.system(size: 13, weight: .semibold)
    static let bdBody = Font.system(size: 13)
    static let bdSmall = Font.system(size: 12)
    static let bdMono = Font.system(size: 12, design: .monospaced)
    static let bdMonoSmall = Font.system(size: 11.5, design: .monospaced)
    static let bdStat = Font.system(size: 30, weight: .semibold, design: .rounded)
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(BD.text3)
    }
}
