import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs

    var body: some View {
        ZStack {
            AmbientBackground()
            if !state.hasKey {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Sidebar()
                            .frame(width: prefs.sidebarCollapsed ? 64 : min(280, max(220, prefs.sidebarWidth)))
                        if !prefs.sidebarCollapsed {
                            PaneDivider(width: $prefs.sidebarWidth, limits: 220...280, label: "Sidebar")
                        }
                        content
                            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

                    }
                    .environment(\.sidebarCollapsed, prefs.sidebarCollapsed)
                    .onChange(of: geo.size.width < 900) { _, narrow in
                        if narrow { prefs.sidebarCollapsed = true }
                    }
                }
                .transition(.opacity)
            }
            if state.showPalette {
                CommandPalette()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { prefs.sidebarCollapsed.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle sidebar (⌘\\)")
                .accessibilityLabel("Toggle sidebar")
                .disabled(!state.hasKey)
            }
        }
        .overlay(alignment: .bottomTrailing) { ToastOverlay() }
        .animation(BD.spring, value: state.hasKey)
        .animation(BD.snappy, value: state.showPalette)
        .id(state.sessionID)
        .task(id: state.sessionID) { await state.refreshAll() }
        .sheet(isPresented: $state.showNewSandbox) {
            NewSandboxSheet().environmentObject(state).environmentObject(prefs)
        }
    }

    @ViewBuilder var content: some View {
        ZStack {
            switch state.section {
            case .home: HomeView()
            case .sandboxes: SandboxesView()
            case .environments: EnvironmentsView()
            case .snapshots: SnapshotsView()
            case .webhooks: WebhooksView()
            case .apiKeys: APIKeysView()
            case .account: AccountView()
            case .cli: CLIConsoleView()
            }
        }
        .id(state.section)
        .transition(.identity)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.openSettings) private var openSettings

    @Environment(\.sidebarCollapsed) var collapsed
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var accountLabel: String {
        let user = state.me?["user"] ?? state.me ?? .null
        let identifier = user.first("login", "username", "email")?.string ?? "Account"
        return identifier.split(separator: "@").first.map(String.init) ?? "Account"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand stays below the native window toolbar.
            HStack(spacing: 10) {
                LogoMark(size: 26)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Boat Deck").font(.system(size: 14, weight: .semibold)).foregroundStyle(BD.text)
                        Text("boat.dev control").font(.system(size: 11.5)).foregroundStyle(BD.text2)
                    }
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18).padding(.horizontal, collapsed ? 17 : 16).padding(.bottom, 18)

            Button { state.showPalette = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11.5))
                    if !collapsed {
                        Text("Search or jump…").font(.bdBody).lineLimit(1)
                        Spacer()
                        Text("⌘K").font(.system(size: 10.5, weight: .medium)).foregroundStyle(BD.text3)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(BD.surface, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .foregroundStyle(BD.text2)
                .padding(.horizontal, collapsed ? 0 : 10)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(BD.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    group("Workspace", NavSection.workspace)
                    group("Manage", NavSection.admin).padding(.top, 14)
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)

            if !collapsed { CreditCard().padding(.horizontal, 12).padding(.bottom, 10).transition(.opacity) }

            HStack(spacing: 8) {
                Button { state.go(.account) } label: {
                    HStack(spacing: 8) {
                        Avatar(name: accountLabel, size: 28)
                        if !collapsed {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(accountLabel).font(.system(size: 12.5, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                                HStack(spacing: 4) {
                                    Circle().fill(connColor).frame(width: 5, height: 5)
                                    Text(connText).font(.system(size: 11)).foregroundStyle(BD.text2)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Account")
                .accessibilityLabel("Account")
                if !collapsed {
                    Spacer(minLength: 0)
                    IconButton(icon: "gearshape", help: "Settings (⌘,)", size: 30) { openSettings() }
                }
            }
            .padding(.horizontal, collapsed ? 17 : 14).padding(.bottom, collapsed ? 10 : 18)

            if collapsed {
                IconButton(icon: "gearshape", help: "Settings (⌘,)", size: 30) { openSettings() }
                    .frame(maxWidth: .infinity).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background {
            if prefs.glass && !reduceTransparency {
                SidebarMaterial().overlay(BD.bg.opacity(0.12)).ignoresSafeArea()
            } else {
                BD.bgRaised.ignoresSafeArea()
            }
        }
    }

    var connColor: Color {
        switch state.connection { case .ok: return BD.green; case .failed: return BD.red; case .unknown: return BD.amber }
    }
    var connText: String {
        switch state.connection { case .ok: return "Connected"; case .failed: return "Connection problem"; case .unknown: return "Connecting…" }
    }

    func group(_ title: String, _ items: [NavSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !collapsed { Eyebrow(text: title).padding(.leading, 10).padding(.bottom, 4) }
            ForEach(items) { s in SidebarItem(section: s) }
        }
    }
}

struct SidebarItem: View {
    let section: NavSection
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.sidebarCollapsed) var collapsed
    @VState private var hover = false

    var selected: Bool { state.section == section }

    var badge: String? {
        switch section {
        case .sandboxes: return state.sandboxes.isEmpty ? nil : "\(state.runningCount)"
        case .environments: return state.environments.isEmpty ? nil : "\(state.environments.count)"
        case .snapshots: return state.namedSnapshots.isEmpty ? nil : "\(state.namedSnapshots.count)"
        default: return nil
        }
    }

    var body: some View {
        Button {
            state.go(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? section.filledIcon : section.icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(selected ? BD.text : BD.text2)
                if !collapsed {
                    Text(section.rawValue).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? BD.text : BD.text2)
                    Spacer()
                    if let badge {
                        Text(badge).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(BD.text2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(BD.surfaceHi, in: Capsule())
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(BD.surfaceHi)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
                } else if hover {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BD.surface)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(collapsed ? section.rawValue : "")
        .accessibilityLabel(section.rawValue)
    }
}

struct CreditCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let hours = state.creditHours
        let running = state.concurrency.0
        let limit = state.concurrency.1
        HStack(spacing: 12) {
            RingGauge(value: limit.map { running / max(1, $0) } ?? 0, lineWidth: 4, color: BD.text)
                .frame(width: 30, height: 30)
                .overlay(Text("\(Int(running))").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(BD.text))
            VStack(alignment: .leading, spacing: 2) {
                Text(hours.map { String(format: "%.1f h", $0) } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(BD.text)
                    .contentTransition(.numericText())
                Text("credit · \(Int(running))\(limit.map { "/\(Int($0))" } ?? "") running")
                    .font(.system(size: 11.5)).foregroundStyle(BD.text2).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(BD.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .tapAction { state.go(.account) }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 28
    var body: some View {
        let initials = name.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." }).prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        Circle()
            .fill(LinearGradient(colors: [BD.text.opacity(0.9), BD.text.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Text(initials.isEmpty ? "B" : initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(BD.inverse))
    }
}

/// Brand mark: a sail inside a rounded tile.
struct LogoMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [BD.text, BD.text.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            SailShape()
                .fill(BD.inverse)
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct SailShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // main sail
        p.move(to: CGPoint(x: r.minX + r.width * 0.52, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.52, y: r.minY + r.height * 0.72))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.95, y: r.minY + r.height * 0.72))
        p.closeSubpath()
        // jib
        p.move(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.14))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.72))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.10, y: r.minY + r.height * 0.72))
        p.closeSubpath()
        // hull
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.80))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.80))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.82, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.18, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

