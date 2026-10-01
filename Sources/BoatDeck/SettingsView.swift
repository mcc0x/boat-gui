import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", account = "Account", appearance = "Appearance", sandboxes = "Sandboxes",
         agent = "Agent", notifications = "Notifications", cli = "CLI", advanced = "Advanced", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.crop.circle"
        case .appearance: return "paintpalette"
        case .sandboxes: return "shippingbox"
        case .agent: return "sparkles"
        case .notifications: return "bell.badge"
        case .cli: return "terminal"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @VState private var pane: SettingsPane = .general
    @VNamespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    LogoMark(size: 22)
                    Text("Settings").font(.system(size: 14, weight: .semibold)).foregroundStyle(BD.text)
                }
                .padding(.leading, 8).padding(.top, 40).padding(.bottom, 14)
                ForEach(SettingsPane.allCases) { p in
                    Button { withAnimation(BD.snappy) { pane = p } } label: {
                        HStack(spacing: 9) {
                            Image(systemName: p.icon).font(.system(size: 12.5)).frame(width: 18)
                            Text(p.rawValue).font(.system(size: 12.5, weight: pane == p ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(pane == p ? BD.text : BD.text2)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background {
                            if pane == p {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(BD.surfaceHi)
                                    .matchedGeometryEffect(id: "pane", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 190)
            .background(BD.bg.opacity(0.5))
            Rectangle().fill(BD.stroke).frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pane.rawValue).font(.system(size: 22, weight: .semibold)).foregroundStyle(BD.text)
                    Group {
                        switch pane {
                        case .general: GeneralPane()
                        case .account: AccountPane()
                        case .appearance: AppearancePane()
                        case .sandboxes: SandboxDefaultsPane()
                        case .agent: AgentPane()
                        case .notifications: NotificationsPane()
                        case .cli: CLIPane()
                        case .advanced: AdvancedPane()
                        case .about: AboutPane()
                        }
                    }
                    .id(pane)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 780, height: 560)
        .background(AmbientBackground())
    }
}

// MARK: - Building blocks

struct SettingsGroup<C: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Eyebrow(text: title).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .glassCard(radius: 14, padding: 0)
        }
    }
}

struct SettingsRow<C: View>: View {
    let title: String
    var sub: String = ""
    var icon: String? = nil
    var last = false
    @ViewBuilder var control: () -> C
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12)).foregroundStyle(BD.text2)
                        .frame(width: 26, height: 26).background(BD.surfaceHi, in: RoundedRectangle(cornerRadius: 7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text)
                    if !sub.isEmpty { Text(sub).font(.bdSmall).foregroundStyle(BD.text3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 16)
                control()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if !last { Hairline().padding(.leading, 14) }
        }
    }
}

// MARK: - Panes

struct GeneralPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    var body: some View {
        SettingsGroup(title: "Startup") {
            SettingsRow(title: "Launch at login", sub: "Start Boat Deck when you log in to your Mac.", icon: "power") {
                Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 })).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Show in menu bar", sub: "Quick status and actions from the menu bar; keeps running when the window closes.", icon: "menubar.rectangle") {
                Toggle("", isOn: $prefs.showMenuBar).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Open to", icon: "rectangle.portrait.on.rectangle.portrait", last: true) {
                Picker("", selection: $state.defaultSection) {
                    ForEach(NavSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
        }
        SettingsGroup(title: "Behavior") {
            SettingsRow(title: "Refresh interval", sub: "How often sandbox states are polled.", icon: "arrow.clockwise") {
                PillPicker(options: [5.0, 10, 30, 60].map { PillOption(value: $0, label: "\(Int($0))s") }, selection: $state.refreshSeconds)
            }
            SettingsRow(title: "Skip confirmations", sub: "Don't ask before rotate / revoke. Deletes always ask.", icon: "checkmark.shield", last: true) {
                Toggle("", isOn: $state.skipConfirm).toggleStyle(.switch).labelsHidden()
            }
        }
        .onChange(of: state.refreshSeconds) { _, _ in state.startPolling() }
    }
}

struct AccountPane: View {
    @EnvironmentObject var state: AppState
    @VState private var key = ""
    @VState private var endpoint = ""
    @VState private var organization = ""
    @VState private var testing = false
    var masked: String {
        let k = state.apiKey
        guard k.count > 10 else { return k.isEmpty ? "Not set" : "••••" }
        return String(k.prefix(6)) + String(repeating: "•", count: 10) + String(k.suffix(4))
    }
    var body: some View {
        SettingsGroup(title: "Connection") {
            SettingsRow(title: "Signed in as", sub: state.userEmail ?? state.userName, icon: "person.crop.circle") {
                statusPill
            }
            SettingsRow(title: "API key", sub: masked, icon: "key.fill") {
                Button { Task { testing = true; await state.testConnection(); testing = false } } label: {
                    HStack(spacing: 6) { if testing { Spinner(size: 11) }; Text("Test") }
                }
                .bdButton(.secondary, .small)
            }
            SettingsRow(title: "Replace key", icon: "arrow.triangle.2.circlepath", last: true) {
                HStack {
                    Field(placeholder: "boat_…", text: $key, mono: true, secure: true).frame(width: 180)
                    Button("Save") { if state.setAPIKey(key) { key = ""; Task { await state.refreshAll(); await state.testConnection() } } }
                        .bdButton(.primary, .small).disabled(key.isEmpty)
                }
            }
        }
        SettingsGroup(title: "Endpoint") {
            SettingsRow(title: "API base URL", icon: "network") {
                Field(placeholder: "https://boat.dev/api/v1", text: $endpoint, mono: true).frame(width: 260)
            }
            SettingsRow(title: "Organization", sub: "Bill against an org wallet (leave empty for your active wallet).", icon: "building.2", last: true) {
                Field(placeholder: "org name or id", text: $organization).frame(width: 200)
            }
            SettingsRow(title: "Apply connection", sub: "Your API key is sent to the selected server.", icon: "checkmark.circle", last: true) {
                Button("Save endpoint") { state.configureConnection(url: endpoint, organization: organization) }
                    .bdButton(.primary, .small)
            }
        }
        .onAppear { endpoint = state.apiURL; organization = state.org }
        SettingsGroup {
            SettingsRow(title: "Sign out", sub: "Removes the saved API key from this Mac.", icon: "rectangle.portrait.and.arrow.right", last: true) {
                Button("Sign out") {
                    if confirm("Sign out?", "Your saved API key will be removed from this Mac.", destructive: "Sign out") { Task { await state.signOut() } }
                }
                .bdButton(.danger, .small)
            }
        }
    }
    var statusPill: some View {
        let (text, color): (String, Color) = {
            switch state.connection {
            case .ok: return ("Connected", BD.green)
            case .failed: return ("Failed", BD.red)
            case .unknown: return ("Unknown", BD.amber)
            }
        }()
        return HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(text).font(.bdSmall).foregroundStyle(BD.text) }
            .padding(.horizontal, 9).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
            .help({ if case .failed(let m) = state.connection { return m }; return "" }())
    }
}

struct AppearancePane: View {
    @EnvironmentObject var prefs: UIPrefs
    var body: some View {
        SettingsGroup(title: "Theme") {
            HStack(spacing: 12) {
                ForEach(ThemeChoice.allCases) { t in
                    Button { withAnimation(BD.spring) { prefs.theme = t } } label: {
                        VStack(spacing: 8) {
                            ThemeThumb(theme: t)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(prefs.theme == t ? BD.text : BD.stroke, lineWidth: prefs.theme == t ? 2 : 1))
                            Text(t.rawValue.capitalized).font(.system(size: 12, weight: prefs.theme == t ? .semibold : .regular)).foregroundStyle(BD.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        SettingsGroup(title: "Accent") {
            HStack(spacing: 12) {
                ForEach(AccentChoice.allCases) { a in
                    Button { withAnimation(BD.snappy) { prefs.accent = a } } label: {
                        ZStack {
                            Circle().fill(a.color).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(BD.stroke, lineWidth: 1))
                            if prefs.accent == a {
                                Circle().strokeBorder(BD.text, lineWidth: 2).frame(width: 34, height: 34)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(a.label)
                }
                Spacer()
                Text(prefs.accent.label).font(.bdSmall).foregroundStyle(BD.text2)
            }
            .padding(14)
        }
        SettingsGroup(title: "Materials & motion") {
            SettingsRow(title: "Liquid glass", sub: "Translucent glass surfaces. Turn off for solid panels.", icon: "drop") {
                Toggle("", isOn: $prefs.glass.animation(BD.spring)).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Ambient background", sub: "Soft drifting light and a faint grid behind content.", icon: "sparkles.rectangle.stack") {
                Toggle("", isOn: $prefs.ambient.animation(BD.spring)).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Animations", sub: "Transitions, pulsing status and live waves.", icon: "wand.and.stars") {
                Toggle("", isOn: $prefs.motion).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Density", icon: "rectangle.compress.vertical", last: true) {
                PillPicker(options: [PillOption(value: Density.compact, label: "Compact"), PillOption(value: Density.comfortable, label: "Comfortable")],
                           selection: $prefs.density)
            }
        }
    }
}

struct ThemeThumb: View {
    let theme: ThemeChoice
    var body: some View {
        let dark = Color(white: 0.07), light = Color(white: 0.96)
        ZStack {
            if theme == .system {
                thumb(light, .black)
                thumb(dark, .white).mask(Rectangle().frame(width: 80).frame(maxWidth: .infinity, alignment: .leading))
            } else {
                thumb(theme == .dark ? dark : light, theme == .dark ? .white : .black)
            }
        }
        .frame(width: 160, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    func thumb(_ bg: Color, _ fg: Color) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(fg.opacity(0.08)).frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.7)).frame(width: 50, height: 6)
                    RoundedRectangle(cornerRadius: 5).fill(fg.opacity(0.08)).frame(height: 22)
                    RoundedRectangle(cornerRadius: 5).fill(fg.opacity(0.08)).frame(height: 22)
                }
            }
            .padding(8)
        }
    }
}

struct SandboxDefaultsPane: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsGroup(title: "New sandbox defaults") {
            SettingsRow(title: "Machine size", icon: "cpu") {
                PillPicker(options: [PillOption(value: "small", label: "Small"), PillOption(value: "default", label: "Default"),
                                     PillOption(value: "large", label: "Large")], selection: $state.defaultType)
            }
            SettingsRow(title: "Auto-stop after", sub: "Sandboxes stop (and snapshot) themselves after this long.", icon: "hourglass") {
                Picker("", selection: $state.defaultTTLHours) {
                    ForEach([0.25, 0.5, 1, 2, 4, 8, 12, 24], id: \.self) { h in
                        Text(h < 1 ? "\(Int(h * 60)) minutes" : "\(Int(h)) hour\(h == 1 ? "" : "s")").tag(h)
                    }
                }
                .labelsHidden().frame(width: 150)
            }
            SettingsRow(title: "Environment", icon: "leaf") {
                Picker("", selection: $state.defaultEnvironment) {
                    Text("Account default").tag("")
                    ForEach(state.environments) { e in Text(e.displayName).tag(e["name"] ?? e.id) }
                }
                .labelsHidden().frame(width: 180)
            }
            SettingsRow(title: "Open after launching", sub: "Jump straight to the new sandbox.", icon: "arrow.up.forward.square", last: true) {
                Toggle("", isOn: $state.openAfterCreate).toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

struct AgentPane: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsGroup(title: "Defaults for new prompts") {
            SettingsRow(title: "Agent", icon: "cpu") {
                Picker("", selection: $state.agentProvider) {
                    Text("Boat default").tag("")
                    ForEach(state.catalog.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
            SettingsRow(title: "Model", icon: "brain") {
                Picker("", selection: $state.agentModel) {
                    Text("Boat default").tag("")
                    ForEach(state.catalog[state.agentProvider] ?? [], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
            SettingsRow(title: "Reasoning effort", icon: "dial.medium", last: true) {
                Picker("", selection: $state.agentEffort) {
                    Text("Default").tag("")
                    ForEach(["none", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
        }
        SettingsGroup(title: "Transcript") {
            SettingsRow(title: "Expand tool calls", sub: "Show tool inputs and outputs expanded by default.", icon: "wrench.and.screwdriver", last: true) {
                Toggle("", isOn: $state.expandTools).toggleStyle(.switch).labelsHidden()
            }
        }
        .task { if state.catalog.isEmpty { await state.loadCatalog() } }
    }
}

struct NotificationsPane: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsGroup(title: "Sandbox notifications") {
            SettingsRow(title: "Enable notifications", sub: "macOS notifications when a sandbox changes state.", icon: "bell") {
                Toggle("", isOn: $state.notifyOnStateChange).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Ready", icon: "checkmark.circle") { Toggle("", isOn: $state.notifyReady).toggleStyle(.switch).labelsHidden() }
                .disabled(!state.notifyOnStateChange)
            SettingsRow(title: "Error", icon: "exclamationmark.triangle") { Toggle("", isOn: $state.notifyError).toggleStyle(.switch).labelsHidden() }
                .disabled(!state.notifyOnStateChange)
            SettingsRow(title: "Stopped / archived", icon: "archivebox") { Toggle("", isOn: $state.notifyArchived).toggleStyle(.switch).labelsHidden() }
                .disabled(!state.notifyOnStateChange)
            SettingsRow(title: "Play sound", icon: "speaker.wave.2", last: true) { Toggle("", isOn: $state.notifySound).toggleStyle(.switch).labelsHidden() }
                .disabled(!state.notifyOnStateChange)
        }
    }
}

struct CLIPane: View {
    @EnvironmentObject var state: AppState
    @VState private var version = ""
    var body: some View {
        SettingsGroup(title: "boat CLI") {
            SettingsRow(title: "Status", sub: state.cliPath ?? "Not found on this Mac", icon: "terminal") {
                HStack(spacing: 5) {
                    Circle().fill(state.cliPath == nil ? BD.red : BD.green).frame(width: 6, height: 6)
                    Text(state.cliPath == nil ? "Missing" : (version.isEmpty ? "Installed" : version)).font(.bdSmall).foregroundStyle(BD.text)
                }
                .padding(.horizontal, 9).padding(.vertical, 3).background(BD.surface, in: Capsule())
            }
            SettingsRow(title: "Custom path", sub: "Leave empty to auto-detect.", icon: "folder") {
                HStack {
                    Field(placeholder: "/usr/local/bin/boat", text: $state.cliPathOverride, mono: true).frame(width: 220)
                    Button("Detect") { state.relocateCLI() }.bdButton(.secondary, .small)
                }
            }
            SettingsRow(title: "Install / update", sub: "Runs the official installer or `boat self-update` in Terminal.", icon: "arrow.down.circle", last: true) {
                HStack {
                    Button("Install") { BoatCLI.openInTerminal("/bin/zsh", ["-lc", "curl -fsSL https://boat.dev/install | sh"]) }.bdButton(.secondary, .small)
                    Button("Update") { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["self-update"]) } }.bdButton(.secondary, .small).disabled(state.cliPath == nil)
                    Button("Log in") { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["login"]) } }.bdButton(.secondary, .small).disabled(state.cliPath == nil)
                }
            }
        }
        Text("The CLI uses its own saved login for SSH, port forwarding, snapshot pulls and account administration. Boat Deck asks which CLI account to use and passes the selected server and wallet explicitly. API errors are never retried through the CLI.")
            .font(.bdSmall).foregroundStyle(BD.text3)
            .task(id: state.cliPath) {
                guard let p = state.cliPath else { return }
                let r = await BoatCLI.run(p, ["--version"], timeout: 10)
                version = stripANSI(r.stdout).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
            }
    }
}

struct AdvancedPane: View {
    @EnvironmentObject var state: AppState
    @AppStorage("debugTrace") private var trace = false
    var body: some View {
        SettingsGroup(title: "Diagnostics") {
            SettingsRow(title: "Log API traffic", sub: "Logs status, timing and byte counts only. No bodies, credentials or URL parameters.", icon: "doc.text.magnifyingglass") {
                Toggle("", isOn: $trace).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Reveal log", icon: "folder", last: true) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Trace.dir.appendingPathComponent("api-metadata.log")])
                }
                .bdButton(.secondary, .small)
            }
        }
        SettingsGroup(title: "Data") {
            SettingsRow(title: "Clear activity history", icon: "clock.arrow.circlepath") {
                Button("Clear") { state.clearActivity(); state.toast("Activity cleared") }.bdButton(.secondary, .small)
            }
            SettingsRow(title: "Reset preferences", sub: "Restore appearance and defaults. Your API key is kept.", icon: "arrow.uturn.backward", last: true) {
                Button("Reset") {
                    guard confirm("Reset preferences?", "Appearance, defaults and layout go back to factory settings.", destructive: "Reset") else { return }
                    if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                    state.toast("Preferences reset — restart Boat Deck")
                }
                .bdButton(.danger, .small)
            }
        }
    }
}

struct AboutPane: View {
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var body: some View {
        VStack(spacing: 16) {
            LogoMark(size: 80)
            Text("Boat Deck").font(.system(size: 26, weight: .semibold)).foregroundStyle(BD.text)
            Text("Version \(version)").font(.bdBody).foregroundStyle(BD.text2)
            Text("A native macOS control room for boat.dev cloud sandboxes.").font(.bdBody).foregroundStyle(BD.text3)
            HStack {
                Link(destination: URL(string: "https://docs.boat.dev/quickstart")!) { Label("Docs", systemImage: "book") }.buttonStyle(BDButtonStyle())
                Link(destination: URL(string: "https://boat.dev")!) { Label("boat.dev", systemImage: "safari") }.buttonStyle(BDButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassCard()
    }
}
