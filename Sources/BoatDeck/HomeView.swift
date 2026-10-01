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
            HeroBanner(greeting: greeting).appear()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                StatTile(title: "Active", value: "\(state.runningCount)",
                         sub: "\(state.sandboxes.count) sandboxes total", icon: "shippingbox",
                         ring: concurrencyRatio, ringColor: BD.green)
                    .appear(delay: 0.03)
                StatTile(title: "Credit", value: state.creditHours.map { String(format: "%.1fh", $0) } ?? "—",
                         sub: packText, icon: "clock")
                    .appear(delay: 0.06)
                StatTile(title: "Starts today", value: startsText, sub: "rate limit remaining", icon: "bolt",
                         ring: startsRatio, ringColor: BD.text)
                    .appear(delay: 0.09)
                StatTile(title: "Environments", value: "\(state.environments.count)",
                         sub: "\(state.namedSnapshots.count) named snapshots", icon: "leaf")
                    .appear(delay: 0.12)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Eyebrow(text: "Recent sandboxes")
                        Spacer()
                        Button("View all") { withAnimation(BD.spring) { state.section = .sandboxes } }.bdButton(.ghost, .small)
                    }
                    if state.sandboxes.isEmpty && state.loadedOnce {
                        EmptyStateView(icon: "shippingbox", title: "No sandboxes yet",
                                       message: "Spin up an isolated Linux VM with Docker, Node, Python, Go, Rust and coding agents.",
                                       actionTitle: "Launch a sandbox") { state.showNewSandbox = true }
                            .frame(height: 300)
                    } else if !state.loadedOnce {
                        VStack(spacing: 0) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { i, s in
                                SandboxCard(s: s).appear(delay: 0.03 * Double(i))
                                    .onTapGesture { state.open(sandbox: s.id) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .glassCard()

                VStack(spacing: 14) {
                    StateMixCard()
                    ActivityCard()
                }
                .frame(width: 330)
            }
            .appear(delay: 0.15)
        }
    }

    var recent: [Record] {
        Array(state.sandboxes.sorted { ($0["createdAt"] ?? "") > ($1["createdAt"] ?? "") }.prefix(6))
    }
    var concurrencyRatio: Double? {
        guard let c = state.limits?["concurrency"], let l = c["limit"]?.double, l > 0 else { return nil }
        return (c["running"]?.double ?? Double(state.runningCount)) / l
    }
    var startsText: String {
        guard let d = state.limits?["starts"]?["day"] else { return "—" }
        return d["remaining"]?.string ?? "—"
    }
    var startsRatio: Double? {
        guard let d = state.limits?["starts"]?["day"], let l = d["limit"]?.double, l > 0 else { return nil }
        return (d["remaining"]?.double ?? 0) / l
    }
    var packText: String {
        if let d = state.limits?.first("packBalanceDollars")?.double { return String(format: "$%.2f in packs", d) }
        return state.limits?["canStart"]?.bool == false ? "can't start — top up" : "plan + credit packs"
    }
}

struct HeroBanner: View {
    let greeting: String
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs

    var body: some View {
        ZStack(alignment: .leading) {
            WaveField().opacity(0.9)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date(), format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(BD.text3).textCase(.uppercase)
                    Text(greeting).font(.system(size: 30, weight: .semibold)).foregroundStyle(BD.text)
                    Text(summary).font(.bdBody).foregroundStyle(BD.text2)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { state.showPalette = true } label: { Label("Search", systemImage: "command") }.bdButton(.secondary, .large)
                    Button { Task { await state.quickLaunch() } } label: { Label("Quick launch", systemImage: "bolt.fill") }
                        .bdButton(.secondary, .large)
                    Button { state.showNewSandbox = true } label: { Label("New sandbox", systemImage: "plus") }
                        .bdButton(.primary, .large)
                }
            }
            .padding(26)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: BD.r4, style: .continuous))
        .glassCard(radius: BD.r4, padding: 0)
    }

    var summary: String {
        let n = state.runningCount
        if !state.loadedOnce { return "Syncing with boat.dev…" }
        if n == 0 { return "All quiet on deck. No sandboxes are running right now." }
        return "\(n) sandbox\(n == 1 ? " is" : "es are") running."
    }
}

/// Animated line-wave field used as hero art.
struct WaveField: View {
    @EnvironmentObject var prefs: UIPrefs
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !prefs.motion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let lines = 14
                for i in 0..<lines {
                    var p = Path()
                    let base = size.height * (0.25 + 0.6 * Double(i) / Double(lines))
                    let amp = 6 + Double(i) * 1.4
                    let phase = t * (0.35 + Double(i) * 0.02) + Double(i) * 0.5
                    stride(from: 0.0, through: Double(size.width), by: 6).forEach { x in
                        let y = base + sin(x / 90 + phase) * amp + sin(x / 37 - phase * 0.7) * amp * 0.25
                        if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let fade = 0.02 + 0.07 * Double(i) / Double(lines)
                    ctx.stroke(p, with: .color(BD.text.opacity(fade)), lineWidth: 1)
                }
            }
        }
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
    }
}

struct StateMixCard: View {
    @EnvironmentObject var state: AppState
    struct Slice: Identifiable { let id: String; let count: Int }

    var slices: [Slice] {
        Dictionary(grouping: state.sandboxes, by: { $0.state }).map { Slice(id: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Fleet")
            HStack(spacing: 16) {
                ZStack {
                    if slices.isEmpty {
                        Circle().stroke(BD.surfaceHi, lineWidth: 12)
                    } else {
                        Chart(slices) { s in
                            SectorMark(angle: .value("Count", s.count), innerRadius: .ratio(0.68), angularInset: 2)
                                .cornerRadius(3)
                                .foregroundStyle(colorForState(s.id))
                        }
                        .chartLegend(.hidden)
                    }
                    VStack(spacing: 0) {
                        Text("\(state.sandboxes.count)").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(BD.text)
                            .contentTransition(.numericText())
                        Text("total").font(.system(size: 10)).foregroundStyle(BD.text3)
                    }
                }
                .frame(width: 104, height: 104)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct ActivityCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Activity")
                Spacer()
                if !state.activity.isEmpty {
                    Button("Clear") { withAnimation(BD.spring) { state.clearActivity() } }.bdButton(.ghost, .small)
                }
            }
            if state.activity.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 22, weight: .light)).foregroundStyle(BD.text3)
                    Text("State changes will show up here as they happen.").font(.bdSmall).foregroundStyle(BD.text3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.activity.prefix(8).enumerated()), id: \.element.id) { i, a in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(colorForState(a.to)).frame(width: 8, height: 8).padding(.top, 4)
                                if i < min(7, state.activity.count - 1) {
                                    Rectangle().fill(BD.stroke).frame(width: 1).frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.system(size: 12, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                                Text(a.from == "—" ? "appeared as \(a.to)" : "\(a.from) → \(a.to)")
                                    .font(.bdSmall).foregroundStyle(BD.text2)
                            }
                            Spacer()
                            Text(a.date, style: .relative).font(.system(size: 10)).foregroundStyle(BD.text3)
                        }
                        .frame(minHeight: 38, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { state.open(sandbox: a.sandboxId) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(BD.spring, value: state.activity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
