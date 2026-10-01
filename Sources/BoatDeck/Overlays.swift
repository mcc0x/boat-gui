import SwiftUI

// MARK: - Command palette (⌘K)

struct PaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let group: String
    var state: String? = nil
    let action: () -> Void
}

struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.openSettings) private var openSettings
    @VState private var query = ""
    @VState private var index = 0
    @VFocusState private var focused: Bool
    @VState private var shown = false

    var items: [PaletteItem] {
        var out: [PaletteItem] = []
        out.append(PaletteItem(title: "New sandbox…", subtitle: "Configure and launch", icon: "plus", group: "Actions") { state.showNewSandbox = true })
        out.append(PaletteItem(title: "Quick launch", subtitle: "Default size & lifetime", icon: "bolt.fill", group: "Actions") { Task { await state.quickLaunch() } })
        out.append(PaletteItem(title: "Refresh everything", subtitle: "⌘R", icon: "arrow.clockwise", group: "Actions") { Task { await state.refreshAll() } })
        out.append(PaletteItem(title: "Settings", subtitle: "⌘,", icon: "gearshape", group: "Actions") { openSettings() })
        out.append(PaletteItem(title: "Toggle appearance", subtitle: "Dark ↔ Light", icon: "circle.lefthalf.filled", group: "Actions") {
            prefs.theme = prefs.theme == .dark ? .light : .dark
        })
        for s in NavSection.allCases {
            out.append(PaletteItem(title: "Go to \(s.rawValue)", subtitle: "⌘\(String(s.shortcut.character))", icon: s.icon, group: "Navigate") {
                withAnimation(BD.spring) { state.section = s; if s == .sandboxes { state.selectedSandbox = nil } }
            })
        }
        for sb in state.sandboxes {
            out.append(PaletteItem(title: sb.displayName, subtitle: "\(sb.id) · \(sb.state)", icon: "shippingbox", group: "Sandboxes", state: sb.state) {
                state.open(sandbox: sb.id)
            })
            if sb.isActive, state.cliPath != nil {
                out.append(PaletteItem(title: "SSH into \(sb.displayName)", subtitle: sb.id, icon: "terminal", group: "Sandboxes") {
                    state.openCLI(["ssh", sb.id])
                })
            }
        }
        for e in state.environments {
            out.append(PaletteItem(title: e.displayName, subtitle: "Environment", icon: "leaf", group: "Environments") {
                withAnimation(BD.spring) { state.section = .environments }
            })
        }
        for n in state.namedSnapshots {
            let name = n["name"] ?? n.id
            out.append(PaletteItem(title: "Launch from \(name)", subtitle: "Named snapshot", icon: "tag", group: "Snapshots") {
                Task { await state.run("Launching from \(name)") { try await $0.createSandbox(["from": .string(name)]) } }
            })
        }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(out.prefix(40)) }
        return out.filter { fuzzy(q, $0.title.lowercased()) || $0.subtitle.lowercased().contains(q) }
    }

    func fuzzy(_ q: String, _ s: String) -> Bool {
        if s.contains(q) { return true }
        var it = s.makeIterator()
        for c in q { var found = false; while let n = it.next() { if n == c { found = true; break } }; if !found { return false } }
        return true
    }

    var body: some View {
        let list = items
        ZStack(alignment: .top) {
            Color.black.opacity(shown ? 0.35 : 0).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(BD.text2)
                    TextField("Search sandboxes, actions, pages…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 16))
                        .focused($focused)
                        .onSubmit { run(list) }
                        .onKeyPress(.downArrow) { index = min(list.count - 1, index + 1); return .handled }
                        .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                    Text("esc").font(.system(size: 10.5, weight: .medium)).foregroundStyle(BD.text3)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(BD.surface, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(16)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if list.isEmpty {
                                Text("No results for “\(query)”").font(.bdBody).foregroundStyle(BD.text3).padding(20)
                            }
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, it in
                                if i == 0 || list[i - 1].group != it.group {
                                    Eyebrow(text: it.group).padding(.horizontal, 12).padding(.top, i == 0 ? 6 : 12).padding(.bottom, 4)
                                }
                                HStack(spacing: 12) {
                                    Image(systemName: it.icon).font(.system(size: 13)).foregroundStyle(BD.text)
                                        .frame(width: 28, height: 28)
                                        .background(i == index ? BD.surfaceHi : BD.surface, in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(it.title).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                                        Text(it.subtitle).font(.bdSmall).foregroundStyle(BD.text3).lineLimit(1)
                                    }
                                    Spacer()
                                    if let s = it.state { StateBadge(state: s) }
                                    if i == index { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(BD.text3) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(i == index ? BD.surface : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                                .tapAction { index = i; run(list) }
                                .onHover { if $0 { index = i } }
                                .id(i)
                            }
                        }
                        .padding(8)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: 420)
                    .onChange(of: index) { _, i in proxy.scrollTo(i, anchor: .center) }
                }
            }
            .frame(width: 620)
            .glassCard(radius: 20, padding: 0)
            .background(BD.bgRaised.opacity(prefs.glass ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
            .padding(.top, 110)
            .scaleEffect(shown ? 1 : 0.96)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            focused = true
            withAnimation(BD.snappy) { shown = true }
        }
        .onChange(of: query) { _, _ in index = 0 }
    }

    func run(_ list: [PaletteItem]) {
        guard list.indices.contains(index) else { return }
        let it = list[index]
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { it.action() }
    }

    func close() {
        withAnimation(BD.snappy) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { state.showPalette = false }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @VState private var key = ""
    @VState private var working = false
    @VState private var msg: String?

    var body: some View {
        ZStack {
            WaveField().opacity(0.8)
            VStack(spacing: 26) {
                LogoMark(size: 76).appear()
                VStack(spacing: 10) {
                    Text("Boat Deck").font(.system(size: 40, weight: .semibold)).foregroundStyle(BD.text)
                    Text("Your boat.dev fleet — sandboxes, agents, environments and snapshots — in one native Mac app.")
                        .font(.system(size: 15)).foregroundStyle(BD.text2).multilineTextAlignment(.center).frame(maxWidth: 460)
                }
                .appear(delay: 0.06)

                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "Connect with an API key")
                    HStack {
                        Field(placeholder: "boat_…", text: $key, mono: true, secure: true)
                        Button("Connect") { if state.setAPIKey(key) { key = ""; Task { await state.refreshAll() } } }
                            .bdButton(.primary).keyboardShortcut(.defaultAction).disabled(key.isEmpty)
                    }
                    HStack {
                        Rectangle().fill(BD.stroke).frame(height: 1)
                        Text("or use the CLI").font(.bdSmall).foregroundStyle(BD.text3).fixedSize()
                        Rectangle().fill(BD.stroke).frame(height: 1)
                    }
                    HStack(spacing: 8) {
                        step(1, "Install", done: state.cliPath != nil) {
                            BoatCLI.openInTerminal("/bin/zsh", ["-lc", "curl -fsSL https://boat.dev/install | sh"])
                        }
                        step(2, "Log in", done: false) { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["login"]) } }
                            .disabled(state.cliPath == nil)
                        step(3, "Create key", done: false) { Task { await createKeyViaCLI() } }
                            .disabled(state.cliPath == nil || working)
                        IconButton(icon: "arrow.clockwise", help: "Detect CLI again") { state.relocateCLI() }
                    }
                    if let msg { Text(msg).font(.bdSmall).foregroundStyle(BD.text2).textSelection(.enabled) }
                }
                .frame(width: 480)
                .glassCard(radius: BD.r4, padding: 22)
                .appear(delay: 0.12)

                Link("Get an API key at boat.dev →", destination: URL(string: "https://docs.boat.dev/quickstart")!)
                    .font(.bdSmall).foregroundStyle(BD.text2)
            }
        }
    }

    func step(_ n: Int, _ title: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(done ? BD.green.opacity(0.2) : BD.surfaceHi).frame(width: 18, height: 18)
                    if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(BD.green) }
                    else { Text("\(n)").font(.system(size: 10, weight: .semibold)).foregroundStyle(BD.text2) }
                }
                Text(title)
            }
        }
        .bdButton(.secondary, .small)
    }

    func createKeyViaCLI() async {
        guard let p = state.cliPath else { return }
        working = true; defer { working = false }
        let name = "boat-deck-\(Host.current().localizedName?.replacingOccurrences(of: " ", with: "-") ?? "mac")"
        let r = await BoatCLI.run(p, ["api-key", "create", name, "--preset", "admin", "--json"])
        let j = r.json
        let secret = j?.first("key", "secret", "token", "apiKey")?.string
            ?? j?["apiKey"]?.first("key", "secret", "token")?.string
            ?? j?["key"]?.first("secret", "key", "token")?.string
        if let secret, r.exitCode == 0 {
            guard state.setAPIKey(secret) else { return }
            await state.refreshAll()
        } else {
            msg = "Couldn't read a key from the CLI (exit \(r.exitCode)). Run “Log in” first, then retry — or paste a key above.\n\(stripANSI(r.stderr + r.stdout).prefix(300))"
        }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LogoMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Boat Deck").font(.system(size: 13, weight: .semibold)).foregroundStyle(BD.text)
                    Text("\(state.runningCount) running · \(state.sandboxes.count) total").font(.system(size: 10.5)).foregroundStyle(BD.text3)
                }
                Spacer()
                if let h = state.creditHours {
                    Text(String(format: "%.1fh", h)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(BD.text)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(BD.surface, in: Capsule())
                }
            }
            Hairline()
            if state.sandboxes.isEmpty {
                Text(state.hasKey ? "No sandboxes" : "Connect an API key in the app").font(.bdSmall).foregroundStyle(BD.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(state.sandboxes.sorted { $0.isActive && !$1.isActive }.prefix(14)) { s in
                        MenuRow(s: s) { show(s.id) }
                    }
                }
            }
            .frame(maxHeight: 320)
            Hairline()
            HStack(spacing: 6) {
                Button { state.showNewSandbox = true; show(nil) } label: { Label("New", systemImage: "plus") }.bdButton(.primary, .small)
                Button { Task { await state.quickLaunch() } } label: { Label("Quick", systemImage: "bolt.fill") }.bdButton(.secondary, .small)
                Spacer()
                IconButton(icon: "arrow.clockwise", help: "Refresh", size: 24) { Task { await state.refreshAll() } }
                IconButton(icon: "macwindow", help: "Open Boat Deck", size: 24) { show(nil) }
                IconButton(icon: "power", help: "Quit", size: 24) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    func show(_ id: String?) {
        if let id { state.open(sandbox: id) }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuRow: View {
    let s: Record
    let open: () -> Void
    @EnvironmentObject var state: AppState
    @VState private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: s.state, size: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.displayName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                Text(s.state).font(.system(size: 10.5)).foregroundStyle(BD.text3)
            }
            Spacer()
            if hover {
                if s.isArchived {
                    IconButton(icon: "play.fill", help: "Resume", size: 22) { Task { await state.run("Resuming") { try await $0.resume(s.id) } } }
                } else {
                    IconButton(icon: "terminal", help: "SSH", size: 22) { state.openCLI(["ssh", s.id]) }
                    IconButton(icon: "stop.fill", help: "Stop", size: 22) { Task { await state.run("Stopping") { try await $0.stop(s.id) } } }
                }
            }
            IconButton(icon: "arrow.up.forward", help: "Open", size: 22, action: open)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hover ? BD.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { h in withAnimation(BD.soft) { hover = h } }
    }
}
