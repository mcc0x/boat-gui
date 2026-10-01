import SwiftUI

// MARK: - Width-driven layout
//
// The content area publishes its width into the environment; views pick column counts and
// what to show from it instead of hard-coding sizes. One level of surface max: content sits on the
// window background, separated by spacing and hairlines; glass is reserved for floating chrome.

enum WidthClass: Comparable { case compact, regular, wide }

private struct ContentWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1000 }
extension EnvironmentValues {
    var contentWidth: CGFloat {
        get { self[ContentWidthKey.self] }
        set { self[ContentWidthKey.self] = newValue }
    }
}

extension CGFloat {
    var widthClass: WidthClass { self < 640 ? .compact : self < 1000 ? .regular : .wide }
}

/// Measures available width and publishes it to children.
struct WidthReader<Content: View>: View {
    @ViewBuilder var content: (CGFloat) -> Content
    @VState private var width: CGFloat = 1000
    var body: some View {
        content(width)
            .environment(\.contentWidth, width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, w in if abs(w - width) > 0.5 { width = w } }
            })
    }
}

// MARK: - Page

/// Scrolling page with width-aware gutters and a readable max width.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 1240
    @ViewBuilder var content: () -> Content
    var body: some View {
        WidthReader { w in
            ScrollView {
                VStack(alignment: .leading, spacing: w.widthClass == .compact ? 22 : 30) { content() }
                    .padding(.horizontal, gutter(w))
                    .padding(.top, 44).padding(.bottom, 36)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
        }
    }
    func gutter(_ w: CGFloat) -> CGFloat { w < 640 ? 18 : w < 1000 ? 26 : 36 }
}

/// Page title row. Trailing actions move under the title when space is tight.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                trailing()
            }
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                trailing()
            }
        }
    }
    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.bdTitle).foregroundStyle(BD.text).lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle).font(.bdBody).foregroundStyle(BD.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "") { self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }) }
}

// MARK: - Flat sections

/// A flat titled section: eyebrow header + optional trailing control, content below. No background.
struct FlatSection<Content: View, Trailing: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(BD.text3) }
                Eyebrow(text: title)
                Spacer(minLength: 8)
                trailing()
            }
            .frame(minHeight: 22)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FlatSection where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, trailing: { EmptyView() }, content: content)
    }
}
extension FlatSection {
    init(_ title: String, icon: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, trailing: trailing, content: content)
    }
}

/// A plain row inside a flat list: hover highlight, hairline below.
struct RowStyle: ViewModifier {
    var divider = true
    var selected = false
    @VState private var hover = false
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 10).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? BD.surfaceHi : hover ? BD.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(BD.soft, value: hover)
            if divider { Hairline().padding(.horizontal, 10) }
        }
    }
}

extension View {
    func listRow(divider: Bool = true, selected: Bool = false) -> some View {
        modifier(RowStyle(divider: divider, selected: selected))
    }
}

// MARK: - Metrics strip

struct Metric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var sub: String = ""
    var icon: String
    var ring: Double? = nil
    var ringColor: Color = BD.text
}

/// A row of headline numbers separated by hairlines (no tiles). Reflows to 2 columns, then 1.
struct MetricStrip: View {
    let metrics: [Metric]
    @Environment(\.contentWidth) var width
    /// Largest column count that fits and divides the metrics evenly (4 → 4, 2 or 1; never 3 + 1).
    var columns: Int {
        let fit = Int(max(1, (width - 40) / 210))
        if fit >= metrics.count { return metrics.count }
        return (1...max(1, fit)).reversed().first { metrics.count % $0 == 0 } ?? 1
    }
    var body: some View {
        let cols = columns
        let rows = stride(from: 0, to: metrics.count, by: cols).map { Array(metrics[$0..<min($0 + cols, metrics.count)]) }
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(Array(rows[r].enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Rectangle().fill(BD.stroke).frame(width: 1).frame(maxHeight: .infinity).padding(.vertical, 4) }
                        MetricCell(m: m).padding(.leading, i == 0 ? 0 : 20).padding(.trailing, 12)
                    }
                    if rows[r].count < cols { Spacer() }
                }
                .fixedSize(horizontal: false, vertical: true)
                if r < rows.count - 1 { Hairline().padding(.vertical, 14) }
            }
        }
    }
}

struct MetricCell: View {
    let m: Metric
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: m.icon).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(BD.text3)
                    Eyebrow(text: m.title)
                }
                Text(m.value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(BD.text)
                    .contentTransition(.numericText())
                    .animation(BD.spring, value: m.value)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(m.sub.isEmpty ? " " : m.sub).font(.bdSmall).foregroundStyle(BD.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let ring = m.ring { RingGauge(value: ring, lineWidth: 5, color: m.ringColor).frame(width: 38, height: 38) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flow layout

/// Wraps children onto new lines when they don't fit (for chips and action buttons).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

/// Two columns when wide, one stacked column otherwise.
struct Columns<Left: View, Right: View>: View {
    var rightWidth: CGFloat = 340
    var breakpoint: CGFloat = 900
    var spacing: CGFloat = 36
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right
    @Environment(\.contentWidth) var width
    var body: some View {
        if width >= breakpoint {
            HStack(alignment: .top, spacing: spacing) {
                left().frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(BD.stroke).frame(width: 1).frame(maxHeight: .infinity)
                right().frame(width: rightWidth, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 30) {
                left()
                Hairline()
                right()
            }
        }
    }
}

private struct SidebarCollapsedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Effective sidebar state (user preference, or forced when the window is narrow).
    var sidebarCollapsed: Bool {
        get { self[SidebarCollapsedKey.self] }
        set { self[SidebarCollapsedKey.self] = newValue }
    }
}

/// HStack when wide enough, VStack otherwise (for list + inspector pairs).
struct AdaptiveStack<Content: View>: View {
    var breakpoint: CGFloat = 900
    var spacing: CGFloat = 28
    @ViewBuilder var content: () -> Content
    @Environment(\.contentWidth) var width
    var body: some View {
        if width >= breakpoint {
            HStack(alignment: .top, spacing: spacing) { content() }
        } else {
            VStack(alignment: .leading, spacing: spacing) { content() }
        }
    }
}
