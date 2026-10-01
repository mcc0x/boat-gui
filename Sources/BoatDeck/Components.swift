import SwiftUI
import AppKit

// MARK: - Buttons

enum BtnKind { case primary, secondary, ghost, danger }

struct BDButtonStyle: ButtonStyle {
    var kind: BtnKind = .secondary
    var size: ControlSize = .regular
    func makeBody(configuration: Configuration) -> some View {
        BDButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct BDButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: BtnKind
    let size: ControlSize
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.isEnabled) var enabled
    @VState private var hover = false

    var body: some View {
        let h: CGFloat = size == .small ? 24 : size == .large ? 36 : 30
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(.system(size: size == .small ? 11.5 : 12.5, weight: .medium))
            .labelStyle(TightLabel())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, size == .small ? 10 : 14)
            .frame(height: h)
            .foregroundStyle(fg)
            .background(bg, in: shape)
            .overlay(shape.strokeBorder(kind == .primary ? Color.clear : (hover ? BD.strokeHi : BD.stroke), lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && prefs.motion ? 0.97 : 1)
            .animation(BD.snappy, value: configuration.isPressed)
            .animation(BD.soft, value: hover)
            .onHover { hover = $0 && enabled }
            .contentShape(shape)
    }

    var fg: Color {
        switch kind {
        case .primary: return prefs.accent.onColor
        case .danger: return BD.red
        default: return BD.text
        }
    }

    var bg: AnyShapeStyle {
        let pressed = configuration.isPressed
        switch kind {
        case .primary: return AnyShapeStyle(prefs.accent.color.opacity(pressed ? 0.8 : hover ? 0.9 : 1))
        case .secondary: return AnyShapeStyle(hover ? BD.surfaceHi : BD.surface)
        case .ghost: return AnyShapeStyle(hover ? BD.surface : Color.clear)
        case .danger: return AnyShapeStyle(BD.red.opacity(hover ? 0.18 : 0.1))
        }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.imageScale(.small); configuration.title }
    }
}

extension View {
    func bdButton(_ kind: BtnKind = .secondary, _ size: ControlSize = .regular) -> some View {
        buttonStyle(BDButtonStyle(kind: kind, size: size))
    }
}

/// Round icon-only button.
struct IconButton: View {
    let icon: String
    var help: String = ""
    var size: CGFloat = 28
    var tint: Color = BD.text2
    let action: () -> Void
    @VState private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(hover ? BD.text : tint)
                .frame(width: size, height: size)
                .background(hover ? BD.surfaceHi : BD.surface, in: Circle())
                .overlay(Circle().strokeBorder(BD.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(BD.soft, value: hover)
    }
}

// MARK: - Status

struct StatusDot: View {
    let state: String
    var size: CGFloat = 8
    @EnvironmentObject var prefs: UIPrefs
    @VState private var pulse = false
    var live: Bool { ["running", "provisioning", "hydrating", "resuming", "archiving", "stopping", "ready"].contains(state) }
    var body: some View {
        ZStack {
            if live && prefs.motion {
                Circle().fill(colorForState(state).opacity(0.4))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 2.3 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle().fill(colorForState(state)).frame(width: size, height: size)
                .shadow(color: colorForState(state).opacity(0.7), radius: live ? 3 : 0)
        }
        .frame(width: size * 2.3, height: size * 2.3)
        .onAppear {
            guard live else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct StateBadge: View {
    let state: String
    var body: some View {
        HStack(spacing: 1) {
            StatusDot(state: state, size: 6)
            Text(state.capitalized).font(.system(size: 11, weight: .medium)).foregroundStyle(BD.text)
        }
        .padding(.leading, 1).padding(.trailing, 9).padding(.vertical, 1)
        .background(colorForState(state).opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(colorForState(state).opacity(0.28), lineWidth: 1))
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var mono = false
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).font(mono ? .bdMonoSmall : .system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(BD.text2)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(BD.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(BD.stroke, lineWidth: 1))
    }
}

/// Monospaced value with a copy button that animates to a checkmark.
struct CopyChip: View {
    let value: String
    var label: String? = nil
    @VState private var copied = false
    var body: some View {
        Button {
            copyToClipboard(value)
            withAnimation(BD.snappy) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(BD.snappy) { copied = false } }
        } label: {
            HStack(spacing: 6) {
                Text(label ?? value).font(.bdMonoSmall).lineLimit(1).truncationMode(.middle)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(copied ? BD.green : BD.text3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(BD.text2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(BD.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BD.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Copy \(value)")
    }
}

// MARK: - Gauges & stats

struct RingGauge: View {
    var value: Double           // 0…1
    var lineWidth: CGFloat = 7
    var color: Color = BD.text
    @EnvironmentObject var prefs: UIPrefs
    @VState private var shown: Double = 0
    var body: some View {
        ZStack {
            Circle().stroke(BD.surfaceHi, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, shown)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 4)
        }
        .onAppear { withAnimation(prefs.motion ? .spring(response: 1.0, dampingFraction: 0.85) : nil) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(BD.spring) { shown = v } }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var sub: String = ""
    var icon: String
    var ring: Double? = nil
    var ringColor: Color = BD.text
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(BD.text3)
                    Eyebrow(text: title)
                }
                Text(value)
                    .font(.bdStat)
                    .foregroundStyle(BD.text)
                    .contentTransition(.numericText())
                    .animation(BD.spring, value: value)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub.isEmpty ? " " : sub).font(.bdSmall).foregroundStyle(BD.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let ring { RingGauge(value: ring, lineWidth: 6, color: ringColor).frame(width: 46, height: 46) }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Loading

struct Shimmer: ViewModifier {
    @VState private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, BD.text.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                }
                .mask(content)
            )
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(BD.surfaceHi).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(BD.surfaceHi).frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(BD.surface).frame(width: 90, height: 8)
            }
            Spacer()
        }
        .padding(12)
        .modifier(Shimmer())
    }
}

struct Spinner: View {
    var size: CGFloat = 14
    var color: Color = BD.text2
    @VState private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true } }
    }
}

// MARK: - Layout pieces

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.bdTitle).foregroundStyle(BD.text)
                if !subtitle.isEmpty { Text(subtitle).font(.bdBody).foregroundStyle(BD.text2) }
            }
            Spacer()
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "") { self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }) }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @EnvironmentObject var prefs: UIPrefs
    @VState private var float = false
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(BD.stroke.opacity(0.6), lineWidth: 1).frame(width: 124, height: 124)
                Circle().fill(BD.surface).frame(width: 84, height: 84)
                Circle().strokeBorder(BD.stroke, lineWidth: 1).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(BD.text2)
                    .offset(y: float ? -3 : 3)
            }
            Text(title).font(.bdH2).foregroundStyle(BD.text)
            if !message.isEmpty {
                Text(message).font(.bdBody).foregroundStyle(BD.text2).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            if let actionTitle, let action { Button(actionTitle, action: action).bdButton(.primary).padding(.top, 4) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if prefs.motion { withAnimation(.easeInOut(duration: 2.2).repeatForever()) { float = true } } }
    }
}

struct PillOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var icon: String? = nil
    var id: String { label }
}

/// Pill-style segmented control with a sliding selection indicator.
struct PillPicker<T: Hashable>: View {
    let options: [PillOption<T>]
    @Binding var selection: T
    @VNamespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                Button { withAnimation(BD.snappy) { selection = o.value } } label: {
                    HStack(spacing: 5) {
                        if let icon = o.icon { Image(systemName: icon).font(.system(size: 11)) }
                        Text(o.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(on ? BD.text : BD.text2)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background {
                        if on {
                            Capsule().fill(BD.surfaceHi)
                                .overlay(Capsule().strokeBorder(BD.strokeHi, lineWidth: 1))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(BD.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(BD.stroke, lineWidth: 1))
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(BD.text3)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.bdBody)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(BD.text3) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).frame(height: 30)
        .background(BD.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(BD.stroke, lineWidth: 1))
    }
}

/// Styled text field.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var secure = false
    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(mono ? .bdMono : .bdBody)
        .padding(.horizontal, 10).frame(height: 30)
        .background(BD.surface, in: RoundedRectangle(cornerRadius: BD.r1, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BD.r1, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
    }
}

struct KVRow: View {
    let key: String
    let value: String?
    var mono = false
    var copy = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.bdBody).foregroundStyle(BD.text2)
            Spacer(minLength: 16)
            if copy, let value, !value.isEmpty {
                CopyChip(value: value)
            } else {
                Text(value ?? "—").font(mono ? .bdMono : .bdBody).foregroundStyle(BD.text)
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 5)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(BD.stroke).frame(height: 1) }
}

/// Generic key/value renderer for any JSON object — ensures every field Boat returns is visible.
struct JSONGrid: View {
    let json: JSON
    var skip: Set<String> = ["ok", "type"]
    var body: some View {
        if let o = json.object {
            VStack(spacing: 0) {
                ForEach(o.keys.sorted().filter { !skip.contains($0) }, id: \.self) { k in
                    let v = o[k]!
                    KVRow(key: k, value: v.string ?? v.compact, mono: true)
                    Hairline()
                }
            }
        } else {
            Text(json.pretty).font(.bdMonoSmall).foregroundStyle(BD.text2).textSelection(.enabled)
        }
    }
}

struct RawJSONButton: View {
    let json: JSON?
    @VState private var show = false
    var body: some View {
        IconButton(icon: "curlybraces", help: "Raw JSON") { show = true }
            .disabled(json == nil)
            .popover(isPresented: $show) {
                ScrollView {
                    Text(json?.pretty ?? "").font(.bdMonoSmall)
                        .textSelection(.enabled).padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 520, height: 460)
            }
    }
}

// MARK: - Toasts

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

struct ToastOverlay: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 8) {
            ForEach(state.toasts) { t in
                HStack(spacing: 10) {
                    Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.isError ? BD.red : BD.green)
                    Text(t.text).font(.bdBody).foregroundStyle(BD.text).lineLimit(3)
                    Button { state.toasts.removeAll { $0.id == t.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(BD.text3)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassCard(radius: 14, padding: 0)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity.combined(with: .scale(scale: 0.95))))
            }
        }
        .animation(BD.spring, value: state.toasts)
        .padding(20)
        .frame(maxWidth: 480)
    }
}

// MARK: - Logs

struct LogView: View {
    let text: String
    var onDark = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(onDark ? Color.white.opacity(0.86) : BD.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

// MARK: - Dialog helpers

func confirm(_ title: String, _ message: String, destructive: String = "Delete") -> Bool {
    if UserDefaults.standard.bool(forKey: "skipConfirm") && destructive != "Delete" { return true }
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .warning
    a.addButton(withTitle: destructive)
    a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
}

func promptText(_ title: String, _ message: String = "", default def: String = "", ok: String = "OK") -> String? {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.addButton(withTitle: ok)
    a.addButton(withTitle: "Cancel")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    tf.stringValue = def
    a.accessoryView = tf
    a.window.initialFirstResponder = tf
    return a.runModal() == .alertFirstButtonReturn ? tf.stringValue : nil
}

func showSecret(_ title: String, _ secret: String) {
    copyToClipboard(secret)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = "Copied to the clipboard. It won't be shown again:\n\n\(secret)"
    a.runModal()
}

func colorForState(_ s: String) -> Color {
    switch s {
    case "ready", "idle": return BD.green
    case "running": return BD.blue
    case "provisioning", "hydrating", "resuming", "archiving", "stopping": return BD.amber
    case "archived", "stopped", "paused": return BD.text3
    case "error", "failed": return BD.red
    default: return BD.text3
    }
}

/// Preset lifetimes as tappable chips (replaces a long ticked slider).
struct DurationChips: View {
    @Binding var hours: Double
    let options: [Double] = [0.25, 0.5, 1, 2, 4, 8, 12, 24]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { h in
                let on = abs(hours - h) < 0.01
                Button { withAnimation(BD.snappy) { hours = h } } label: {
                    Text(h < 1 ? "\(Int(h * 60))m" : "\(Int(h))h")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .fixedSize()
                        .foregroundStyle(on ? BD.inverse : BD.text2)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(on ? AnyShapeStyle(BD.text) : AnyShapeStyle(BD.surface), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : BD.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension View {
    /// Tap handler that is also exposed to accessibility (VoiceOver / automation) as a button press.
    func tapAction(_ action: @escaping () -> Void) -> some View {
        self.contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}
