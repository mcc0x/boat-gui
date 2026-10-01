import SwiftUI
import Combine

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", agent = "Agent", terminal = "Terminal", files = "Files", access = "Access", snapshots = "Snapshots"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .agent: return "sparkles"
        case .terminal: return "terminal"
        case .files: return "folder"
        case .access: return "network"
        case .snapshots: return "camera.aperture"
        }
    }
}

struct SandboxDetailView: View {
    @EnvironmentObject var state: AppState
    let sandboxId: String
    @VState private var tab: DetailTab = .overview
    @VState private var detail: JSON?

    var record: Record? { state.sandboxes.first { $0.id == sandboxId } }
    var sbState: String { record?.state ?? detail?.first("state", "status")?.string ?? "unknown" }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 26).padding(.top, 40).padding(.bottom, 14)
            HStack {
                PillPicker(options: DetailTab.allCases.map { PillOption(value: $0, label: $0.rawValue, icon: $0.icon) }, selection: $tab)
                Spacer()
            }
            .padding(.horizontal, 26).padding(.bottom, 14)
            Group {
                switch tab {
                case .overview: OverviewTab(id: sandboxId, detail: $detail)
                case .agent: AgentView(id: sandboxId)
                case .terminal: TerminalView(id: sandboxId)
                case .files: FilesView(id: sandboxId)
                case .access: AccessTab(id: sandboxId)
                case .snapshots: SandboxSnapshotsTab(id: sandboxId)
                }
            }
            .id(tab)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(BD.snappy, value: tab)
        .task { detail = try? await state.api.sandbox(sandboxId) }
    }

    var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BD.surfaceHi)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
                Image(systemName: "shippingbox.fill").font(.system(size: 22)).foregroundStyle(BD.text)
            }
            .frame(width: 52, height: 52)
            .overlay(alignment: .bottomTrailing) { StatusDot(state: sbState, size: 9).offset(x: 9, y: 9) }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(record?.displayName ?? sandboxId).font(.system(size: 22, weight: .semibold)).foregroundStyle(BD.text)
                        .lineLimit(1)
                    StateBadge(state: sbState)
                }
                HStack(spacing: 6) {
                    CopyChip(value: sandboxId)
                    Chip(text: record?.specs ?? "4 vCPU · 8 GB", icon: "cpu")
                    if let e = record?["environment", "environmentName"] { Chip(text: e, icon: "leaf") }
                    if let ip = detail?.first("machineIp", "ip")?.string { Chip(text: ip, icon: "network", mono: true) }
                }
            }
            Spacer()
            LifecycleButtons(id: sandboxId, sbState: sbState)
        }
    }
}

struct LifecycleButtons: View {
    @EnvironmentObject var state: AppState
    let id: String
    let sbState: String
    @VState private var busy = false

    var archived: Bool { ["archived", "stopped", "paused"].contains(sbState) }

    var body: some View {
        HStack(spacing: 8) {
            if archived {
                Button { act("Resuming") { try await $0.resume(id) } } label: { Label("Resume", systemImage: "play.fill") }
                    .bdButton(.primary)
            } else {
                Button { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["ssh", id]) } } label: { Label("SSH", systemImage: "terminal") }
                    .bdButton().disabled(state.cliPath == nil)
                    .help(state.cliPath == nil ? "Install the boat CLI to use SSH" : "Open an SSH session in Terminal")
                Button { act("Stopping (snapshotting)") { try await $0.stop(id) } } label: {
                    HStack(spacing: 6) { if busy { Spinner(size: 11) } else { Image(systemName: "stop.fill") }; Text("Stop") }
                }
                .bdButton()
            }
            Menu {
                SandboxQuickActions(id: id)
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .background(BD.surface, in: Circle())
            .overlay(Circle().strokeBorder(BD.stroke, lineWidth: 1))
        }
    }

    func act(_ label: String, _ op: @escaping (BoatAPI) async throws -> JSON) {
        busy = true
        Task { await state.run(label, op); busy = false }
    }
}

// MARK: - Overview

struct OverviewTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Binding var detail: JSON?
    @VState private var usage: JSON?
    @VState private var error: String?
    @VState private var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var created: Date? { Date.fromISO(detail?.first("createdAt")?.string) }
    var deadline: Date? { Date.fromISO(detail?.first("archiveAfter", "expiresAt", "autoStopAt")?.string) }
    var neverStops: Bool { detail?["noAutoStop"]?.bool == true || (detail != nil && deadline == nil && detail?["ttlSeconds"]?.double ?? 1 <= 0) }
    var remaining: Double? { deadline.map { $0.timeIntervalSince(now) } }
    /// Whole lifetime window, for the ring (deadline − creation, at least an hour).
    var window: Double {
        guard let d = deadline, let c = created else { return 3600 }
        return max(d.timeIntervalSince(c), remaining ?? 0, 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red).textSelection(.enabled) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    lifetimeCard.appear()
                    usageCard.appear(delay: 0.04)
                    machineCard.appear(delay: 0.08)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Quick actions")
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                        if let u = detail?["url"]?.string, let url = URL(string: u) {
                            Button { NSWorkspace.shared.open(url) } label: { Label("Open URL", systemImage: "safari") }.bdButton(.primary)
                        }
                        Button { rename() } label: { Label("Rename", systemImage: "pencil") }.bdButton()
                        Button { Task { await extend(3600) } } label: { Label("+1 hour", systemImage: "clock.arrow.circlepath") }.bdButton()
                        Button { Task { await extend(4 * 3600) } } label: { Label("+4 hours", systemImage: "clock.badge.plus") }.bdButton()
                        Button {
                            Task { await state.runOrCLI("Auto-stop disabled", cli: ["extend", id, "--no-auto-stop"]) { try await $0.updateSandbox(id, ["noAutoStop": true, "ttlSeconds": 0]) }; await load() }
                        } label: { Label("Keep running", systemImage: "infinity") }.bdButton()
                        Button { Task { await state.run("Forked") { try await $0.fork(id) } } } label: { Label("Fork", systemImage: "arrow.triangle.branch") }.bdButton()
                        Button {
                            if let n = promptText("Snapshot name", "Named snapshots can seed new sandboxes (boat new --from NAME).") {
                                Task { await state.run("Saving snapshot \(n)", refresh: false) { try await $0.saveNamedSnapshot(sandboxId: id, name: n) } }
                            }
                        } label: { Label("Snapshot", systemImage: "camera") }.bdButton()
                        Button { Task { await downloadArtifacts() } } label: { Label("Artifacts", systemImage: "arrow.down.doc") }.bdButton()
                    }.padding(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                .appear(delay: 0.1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack { Eyebrow(text: "All fields"); Spacer(); RawJSONButton(json: detail) }
                    JSONGrid(json: detail ?? .null)
                }
                .glassCard()
                .appear(delay: 0.14)
            }
            .padding(.horizontal, 26).padding(.bottom, 26)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .onReceive(timer) { now = $0 }
    }

    var lifetimeCard: some View {
        let frac: Double = {
            guard let r = remaining else { return 1 }
            return max(0, min(1, r / window))
        }()
        return HStack(spacing: 14) {
            RingGauge(value: frac, lineWidth: 7, color: frac < 0.15 ? BD.amber : BD.text).frame(width: 64, height: 64)
                .overlay(Image(systemName: neverStops ? "infinity" : "hourglass").font(.system(size: 14)).foregroundStyle(BD.text2))
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Auto-stop")
                Text(remainingText).font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(BD.text)
                    .contentTransition(.numericText())
                Text(uptimeText).font(.bdSmall).foregroundStyle(BD.text2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .glassCard()
    }

    var remainingText: String {
        if neverStops { return "Never" }
        guard let r = remaining else { return "—" }
        if r <= 0 { return "Stopping" }
        let h = Int(r) / 3600, m = (Int(r) % 3600) / 60, s = Int(r) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    var uptimeText: String {
        guard let created else { return "uptime —" }
        let up = "up \(durationText(now.timeIntervalSince(created)))"
        if let d = deadline { return up + " · stops at " + d.formatted(date: .omitted, time: .shortened) }
        return up
    }

    var usageCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(BD.surfaceHi)
                Image(systemName: "dollarsign").font(.system(size: 20, weight: .medium)).foregroundStyle(BD.text)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Usage")
                Text(usage?.first("dollars")?.double.map { String(format: "$%.3f", $0) } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(BD.text)
                HStack(spacing: 6) {
                    Text(usage?.first("seconds")?.double.map { durationText($0) + " billed" } ?? "no usage yet")
                    if usage?.first("running")?.bool == true {
                        Circle().fill(BD.green).frame(width: 5, height: 5)
                        Text("metering")
                    }
                }
                .font(.bdSmall).foregroundStyle(BD.text2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .glassCard()
    }

    var machineCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Eyebrow(text: "Machine")
                Spacer()
                if let h = detail?["health"]?.string {
                    HStack(spacing: 4) {
                        Circle().fill(h == "ok" ? BD.green : BD.amber).frame(width: 6, height: 6)
                        Text("health \(h)").font(.system(size: 10.5)).foregroundStyle(BD.text3)
                    }
                }
            }
            .padding(.bottom, 4)
            KVRow(key: "Size", value: [detail?["type"]?.string?.capitalized, detail.map { Record(json: $0).specs }].compactMap { $0 }.joined(separator: " · "))
            KVRow(key: "SSH", value: detail?["sshEndpoint"]?.string, copy: true)
            KVRow(key: "Billing", value: detail?["billingMultiplier"]?.double.map { "\(String(format: "%g", $0))× rate" })
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .glassCard()
    }

    func load() async {
        do { detail = try await state.api.sandbox(id); error = nil } catch { self.error = error.localizedDescription }
        usage = try? await state.api.usage(id)
    }

    func rename() {
        guard let n = promptText("Rename sandbox", default: detail?["name"]?.string ?? "") else { return }
        Task { await state.run("Renamed") { try await $0.updateSandbox(id, ["name": .string(n)]) }; await load() }
    }

    func extend(_ secs: Double) async {
        // New lifetime measured from now: whatever is left plus the extension.
        let ttl = max(0, remaining ?? 0) + secs
        await state.runOrCLI("Extended by \(durationText(secs))", cli: ["extend", id, "--ttl", "\(Int(ttl))"]) {
            try await $0.updateSandbox(id, ["ttlSeconds": .number(ttl.rounded())])
        }
        await load()
    }

    func downloadArtifacts() async {
        do {
            let (data, resp) = try await state.api.artifacts(id)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = resp.suggestedFilename ?? "\(id)-artifacts.tar"
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url); state.toast("Saved \(url.lastPathComponent)") }
        } catch { state.toast("Artifacts failed — \(error.localizedDescription)", error: true) }
    }
}

// MARK: - Access

struct HostedURL: Identifiable { let id = UUID(); let port: Int; let url: String }
struct Forward: Identifiable { let id = UUID(); let label: String; let stop: () -> Void }

struct AccessTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var port = "3000"
    @VState private var title = ""
    @VState private var isPublic = false
    @VState private var hosted: [HostedURL] = []
    @VState private var fwdRemote = "3000"
    @VState private var fwdLocal = ""
    @VState private var forwards: [Forward] = []
    @VState private var sshKey = ""

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                card("Public URL", "globe", "Expose a port on a boat.dev URL with a token.") {
                    HStack {
                        Field(placeholder: "Port", text: $port, mono: true).frame(width: 80)
                        Field(placeholder: "Title (optional)", text: $title)
                    }
                    HStack {
                        Toggle("Public (no token)", isOn: $isPublic).toggleStyle(.switch).controlSize(.small)
                        Spacer()
                        Button { Task { await host() } } label: { Label("Create URL", systemImage: "link") }.bdButton(.primary, .small)
                    }
                    ForEach(hosted) { h in
                        HStack {
                            Chip(text: ":\(h.port)", mono: true)
                            Link(h.url, destination: URL(string: h.url) ?? URL(string: "https://boat.dev")!)
                                .font(.bdSmall).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            CopyChip(value: h.url, label: "copy")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                card("Port forward", "arrow.left.arrow.right", "Tunnel a sandbox port to localhost on this Mac.") {
                    HStack {
                        Field(placeholder: "Remote", text: $fwdRemote, mono: true).frame(width: 90)
                        Image(systemName: "arrow.right").foregroundStyle(BD.text3)
                        Field(placeholder: "Local (same)", text: $fwdLocal, mono: true).frame(width: 110)
                        Spacer()
                        Button { startForward() } label: { Label("Start", systemImage: "play.fill") }.bdButton(.primary, .small)
                            .disabled(state.cliPath == nil)
                    }
                    ForEach(forwards) { f in
                        HStack {
                            StatusDot(state: "running", size: 6)
                            Text(f.label).font(.bdMonoSmall).foregroundStyle(BD.text)
                            Spacer()
                            Button("Stop") { f.stop(); forwards.removeAll { $0.id == f.id } }.bdButton(.danger, .small)
                        }
                    }
                    if state.cliPath == nil { Text("Requires the boat CLI.").font(.bdSmall).foregroundStyle(BD.text3) }
                }
                card("Desktop", "display", "A full GUI desktop for the sandbox in your browser.") {
                    HStack {
                        Button { Task { await openDesktop(vnc: false) } } label: { Label("Open desktop", systemImage: "macwindow") }.bdButton(.primary, .small)
                        Button { Task { await openDesktop(vnc: true) } } label: { Label("noVNC", systemImage: "rectangle.on.rectangle") }.bdButton(.secondary, .small)
                    }
                }
                card("SSH", "terminal", "Shell into the sandbox, or authorize one of your keys.") {
                    HStack {
                        Button { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["ssh", id]) } } label: { Label("Open in Terminal", systemImage: "terminal") }
                            .bdButton(.primary, .small).disabled(state.cliPath == nil)
                        CopyChip(value: "boat ssh \(id)")
                    }
                    HStack {
                        Field(placeholder: "ssh-ed25519 AAAA… public key", text: $sshKey, mono: true)
                        IconButton(icon: "person.badge.key", help: "Use ~/.ssh/id_ed25519.pub") { loadLocalKey() }
                        Button("Add") {
                            let k = sshKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await state.run("SSH key added", refresh: false) { try await $0.addSSHKey(id, publicKey: k) } }
                        }
                        .bdButton(.secondary, .small).disabled(sshKey.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 26).padding(.bottom, 26)
            .animation(BD.spring, value: hosted.count)
            .animation(BD.spring, value: forwards.count)
        }
        .scrollContentBackground(.hidden)
        .onDisappear { forwards.forEach { $0.stop() } }
    }

    func card<C: View>(_ title: String, _ icon: String, _ sub: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(BD.text)
                    .frame(width: 30, height: 30).background(BD.surfaceHi, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.bdH3).foregroundStyle(BD.text)
                    Text(sub).font(.bdSmall).foregroundStyle(BD.text2)
                }
            }
            c()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
        .appear()
    }

    func loadLocalKey() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for f in [".ssh/id_ed25519.pub", ".ssh/id_rsa.pub", ".ssh/id_ecdsa.pub"] {
            if let s = try? String(contentsOf: home.appendingPathComponent(f), encoding: .utf8) { sshKey = s.trimmingCharacters(in: .whitespacesAndNewlines); return }
        }
        state.toast("No public key found in ~/.ssh", error: true)
    }

    func host() async {
        guard let p = Int(port) else { return }
        if let r = await state.run("Port \(p) is live — URL copied", refresh: false, { try await $0.host(id, port: p, title: title, isPublic: isPublic) }),
           let u = r.first("url")?.string {
            hosted.append(HostedURL(port: p, url: u))
            copyToClipboard(u)
        }
    }

    func openDesktop(vnc: Bool) async {
        if let r = await state.run("Desktop ready", refresh: false, { try await $0.desktop(id) }),
           var u = r.first("url", "vncUrl")?.string {
            if vnc { u += (u.contains("?") ? "&" : "?") + "vnc=1" }
            if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        }
    }

    func startForward() {
        guard let cli = state.cliPath else { return }
        var args = ["forward", id, "--remote", fwdRemote]
        if !fwdLocal.isEmpty { args += ["--local", fwdLocal] }
        let (stream, stop) = BoatCLI.stream(cli, args)
        let label = "localhost:\(fwdLocal.isEmpty ? fwdRemote : fwdLocal) → :\(fwdRemote)"
        forwards.append(Forward(label: label, stop: stop))
        Task { for await chunk in stream { if chunk.contains("[exit") { state.toast("Forward ended: \(label)", error: true) } } }
    }
}

// MARK: - Snapshots of one sandbox

struct SandboxSnapshotsTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var snaps: [Record] = []
    @VState private var loaded = false
    @VState private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red).padding(.bottom, 8) }
                if !loaded {
                    ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                } else if snaps.isEmpty {
                    EmptyStateView(icon: "camera.aperture", title: "No snapshots yet", message: "Stopping a sandbox snapshots it automatically.")
                        .frame(height: 300)
                } else {
                    ForEach(Array(snaps.enumerated()), id: \.element.id) { i, s in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle().fill(i == 0 ? BD.text : BD.text3).frame(width: 9, height: 9).padding(.top, 5)
                                if i < snaps.count - 1 { Rectangle().fill(BD.stroke).frame(width: 1).frame(maxHeight: .infinity) }
                            }
                            .frame(width: 9)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(relative(s["createdAt"])).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text)
                                    if i == 0 { Chip(text: "latest") }
                                    if s.json["named"]?.bool == true { Chip(text: "named", icon: "tag") }
                                    if let k = s["kind"] { Chip(text: k == "base" ? "full" : k) }
                                    Spacer()
                                    Text(byteString(s.json.first("sizeBytes", "size")?.double)).font(.bdSmall.monospacedDigit()).foregroundStyle(BD.text2)
                                }
                                HStack(spacing: 6) {
                                    CopyChip(value: s.id)
                                    Text(s["status", "state"] ?? "").font(.bdSmall).foregroundStyle(BD.text3)
                                    Spacer()
                                    Button("Delete") {
                                        guard confirm("Delete snapshot?", s.id) else { return }
                                        Task { await state.run("Snapshot deleted", refresh: false) { try await $0.deleteSnapshot(s.id) }; await load() }
                                    }
                                    .bdButton(.ghost, .small)
                                }
                            }
                            .padding(.bottom, 18)
                        }
                        .appear(delay: 0.03 * Double(i))
                    }
                }
            }
            .glassCard()
            .padding(.horizontal, 26).padding(.bottom, 26)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
    }

    func load() async {
        do { snaps = try await state.api.sandboxSnapshots(id); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}
