import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Working late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let first = state.userName.split(separator: "@").first.map(String.init) ?? state.userName
        return "\(part), \(first)"
    }

    var body: some View {
        Page {
            HomeHeader(greeting: greeting).appear()

            MetricStrip(metrics: [
                Metric(title: "Active", value: "\(state.runningCount)",
                       sub: state.concurrency.1.map { "of \(Int($0)) allowed at once" } ?? "\(state.sandboxes.count) total",
                       icon: "shippingbox", ring: concurrencyRatio, ringColor: BD.green),
                Metric(title: "Credit", value: state.creditHours.map { String(format: "%.1fh", $0) } ?? "—",
                       sub: creditSub, icon: "clock"),
                Metric(title: "Starts left", value: startsText, sub: startsSub, icon: "bolt"),
                Metric(title: "Environments", value: "\(state.environments.count)",
                       sub: "\(state.namedSnapshots.count) named snapshots", icon: "leaf"),
            ])
            .appear(delay: 0.04)

            Hairline()

            Columns(rightWidth: 300, breakpoint: 860) {
                RecentSandboxes()
            } right: {
                VStack(alignment: .leading, spacing: 30) {
                    FleetSection()
                    ActivitySection()
                }
            }
            .appear(delay: 0.08)
        }
    }

    var concurrencyRatio: Double? {
        guard let l = state.concurrency.1, l > 0 else { return nil }
        return state.concurrency.0 / l
    }
    var startsText: String { state.limits?["starts"]?["day"]?["remaining"]?.string ?? "—" }
    var startsSub: String {
        guard let l = state.limits?["starts"]?["day"]?["limit"]?.string else { return "today" }
        return "of \(l) today"
    }
    var startsRatio: Double? {
        guard let d = state.limits?["starts"]?["day"], let l = d["limit"]?.double, l > 0 else { return nil }
        return (d["remaining"]?.double ?? 0) / l
    }
    var creditSub: String {
        if let tier = state.limits?["accessTier"]?.string, tier == "trial" { return "trial balance" }
        if let d = state.limits?.first("packBalanceDollars")?.double, d > 0 { return String(format: "$%.2f in packs", d) }
        return state.limits?["canStart"]?.bool == false ? "can't start — add credit" : "compute balance"
    }
}

struct HomeHeader: View {
    let greeting: String
    @EnvironmentObject var state: AppState
    @Environment(\.contentWidth) var width

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date(), format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(BD.text3).textCase(.uppercase).tracking(0.6)
            PageHeader(title: greeting, subtitle: summary) {
                HStack(spacing: 8) {
                    if width >= 760 {
                        Button { state.showPalette = true } label: { Label("Search", systemImage: "command") }.bdButton()
                    }
                    Button { Task { await state.quickLaunch() } } label: { Label("Quick launch", systemImage: "bolt.fill") }.bdButton()
                    Button { state.showNewSandbox = true } label: { Label("New sandbox", systemImage: "plus") }.bdButton(.primary)
                }
            }
        }
    }

    var summary: String {
        let n = state.runningCount
        if !state.loadedOnce { return "Syncing with boat.dev…" }
        if n == 0 { return "All quiet on deck — no sandboxes running." }
        return "\(n) sandbox\(n == 1 ? " is" : "es are") running."
    }
}

struct RecentSandboxes: View {
    @EnvironmentObject var state: AppState
    var recent: [Record] {
        Array(state.sandboxes.sorted { ($0.isActive ? 0 : 1, $1["createdAt"] ?? "") < ($1.isActive ? 0 : 1, $0["createdAt"] ?? "") }.prefix(8))
    }
    var body: some View {
        FlatSection("Sandboxes", icon: "shippingbox") {
            Button("View all") { state.go(.sandboxes) }.bdButton(.ghost, .small)
        } content: {
            if !state.loadedOnce {
                VStack(spacing: 0) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
            } else if state.sandboxes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No sandboxes yet. Each one is an isolated Linux VM with Docker, Node, Python, Go, Rust and coding agents.")
                        .font(.bdBody).foregroundStyle(BD.text2).fixedSize(horizontal: false, vertical: true)
                    Button { state.showNewSandbox = true } label: { Label("Launch a sandbox", systemImage: "plus") }.bdButton(.primary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { s in
                        SandboxListRow(s: s)
                            .listRow(divider: s.id != recent.last?.id)
                            .tapAction { state.open(sandbox: s.id) }
                            .contextMenu { SandboxQuickActions(id: s.id) }
                    }
                }
            }
        }
    }
}

/// Compact, width-aware sandbox row used on Home and in the Sandboxes list.
struct SandboxListRow: View {
    let s: Record
    @Environment(\.contentWidth) var width
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: s.state, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                Text([s.id, s.specs, s["environment"]].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(BD.text3).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if width >= 700, s.isActive, let d = s.archiveAfter, d > Date() {
                Label(d.formatted(.relative(presentation: .named, unitsStyle: .narrow)), systemImage: "hourglass")
                    .labelStyle(TightLabel()).font(.bdSmall).foregroundStyle(BD.text3).lineLimit(1)
            }
            StateBadge(state: s.state)
        }
    }
}

/// Animated line-wave field used as header art.
struct WaveField: View {
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.controlActiveState) private var active
    var body: some View {
        // Animates only while the window is active, at a modest frame rate, to keep CPU/battery use low.
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !prefs.motion || active == .inactive)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let lines = 10
                for i in 0..<lines {
                    var p = Path()
                    let base = size.height * (0.25 + 0.6 * Double(i) / Double(lines))
                    let amp = 6 + Double(i) * 1.4
                    let phase = t * (0.35 + Double(i) * 0.02) + Double(i) * 0.5
                    stride(from: 0.0, through: Double(size.width), by: 12).forEach { x in
                        let y = base + sin(x / 90 + phase) * amp + sin(x / 37 - phase * 0.7) * amp * 0.25
                        if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let fade = 0.02 + 0.06 * Double(i) / Double(lines)
                    ctx.stroke(p, with: .color(BD.text.opacity(fade)), lineWidth: 1)
                }
            }
        }
        .mask(LinearGradient(colors: [.clear, .black.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
    }
}

struct FleetSection: View {
    @EnvironmentObject var state: AppState
    struct Slice: Identifiable { let id: String; let count: Int }

    var slices: [Slice] {
        Dictionary(grouping: state.sandboxes, by: { $0.state }).map { Slice(id: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        FlatSection("Fleet", icon: "chart.pie") {
            HStack(spacing: 18) {
                ZStack {
                    if slices.isEmpty {
                        Circle().stroke(BD.surfaceHi, lineWidth: 10)
                    } else {
                        Chart(slices) { s in
                            SectorMark(angle: .value("Count", s.count), innerRadius: .ratio(0.7), angularInset: 2)
                                .cornerRadius(3)
                                .foregroundStyle(colorForState(s.id))
                        }
                        .chartLegend(.hidden)
                    }
                    VStack(spacing: 0) {
                        Text("\(state.sandboxes.count)").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(BD.text)
                            .contentTransition(.numericText())
                        Text("total").font(.system(size: 9.5)).foregroundStyle(BD.text3)
                    }
                }
                .frame(width: 86, height: 86)
                .animation(BD.spring, value: state.sandboxes.count)

                VStack(alignment: .leading, spacing: 6) {
                    if slices.isEmpty { Text("No sandboxes").font(.bdSmall).foregroundStyle(BD.text3) }
                    ForEach(slices.prefix(5)) { s in
                        HStack(spacing: 6) {
                            Circle().fill(colorForState(s.id)).frame(width: 7, height: 7)
                            Text(s.id.capitalized).font(.bdSmall).foregroundStyle(BD.text2)
                            Spacer()
                            Text("\(s.count)").font(.bdSmall.monospacedDigit()).foregroundStyle(BD.text)
                        }
                    }
                }
            }
        }
    }
}

struct ActivitySection: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        FlatSection("Activity", icon: "waveform.path.ecg") {
            if !state.activity.isEmpty {
                Button("Clear") { withAnimation(BD.spring) { state.clearActivity() } }.bdButton(.ghost, .small)
            }
        } content: {
            if state.activity.isEmpty {
                Text("State changes show up here as they happen.").font(.bdSmall).foregroundStyle(BD.text3)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let items = Array(state.activity.prefix(8))
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(colorForState(a.to)).frame(width: 7, height: 7).padding(.top, 5)
                                if i < items.count - 1 { Rectangle().fill(BD.stroke).frame(width: 1).frame(maxHeight: .infinity) }
                            }
                            .frame(width: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.system(size: 12, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                                Text(a.from == "—" ? "appeared as \(a.to)" : "\(a.from) → \(a.to)")
                                    .font(.bdSmall).foregroundStyle(BD.text2)
                            }
                            Spacer(minLength: 6)
                            Text(a.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                .font(.system(size: 10)).foregroundStyle(BD.text3)
                        }
                        .frame(minHeight: 40, alignment: .top)
                        .tapAction { state.open(sandbox: a.sandboxId) }
                    }
                }
                .animation(BD.spring, value: state.activity)
            }
        }
    }
}
