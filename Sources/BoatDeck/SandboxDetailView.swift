import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", agent = "Agent", terminal = "Terminal", files = "Files", network = "Ports & Access", snapshots = "Snapshots"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "info.circle"
        case .agent: return "sparkles"
        case .terminal: return "terminal"
        case .files: return "folder"
        case .network: return "network"
        case .snapshots: return "camera"
        }
    }
}

struct SandboxDetailView: View {
    @EnvironmentObject var state: AppState
    let sandboxId: String
    @VState private var tab: DetailTab = .overview

    var record: Record? { state.sandboxes.first { $0.id == sandboxId } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record?.displayName ?? sandboxId).font(.title2.bold()).textSelection(.enabled)
                    HStack(spacing: 8) {
                        StateBadge(state: record?.state ?? "…")
                        Text(sandboxId).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Spacer()
                LifecycleButtons(id: sandboxId, state: record?.state ?? "")
            }
            .padding()
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases) { t in Label(t.rawValue, systemImage: t.icon).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal)
            Divider().padding(.top, 8)
            Group {
                switch tab {
                case .overview: OverviewTab(id: sandboxId)
                case .agent: AgentTab(id: sandboxId)
                case .terminal: TerminalTab(id: sandboxId)
                case .files: FilesTab(id: sandboxId)
                case .network: AccessTab(id: sandboxId)
                case .snapshots: SandboxSnapshotsTab(id: sandboxId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LifecycleButtons: View {
    @EnvironmentObject var state: AppState
    let id: String
    let state_: String
    init(id: String, state: String) { self.id = id; self.state_ = state }

    var archived: Bool { ["archived", "stopped", "paused"].contains(state_) }

    var body: some View {
        HStack(spacing: 6) {
            if archived {
                Button { Task { await state.run("Resuming") { try await $0.resume(id) } } } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { Task { await state.run("Stopping (snapshotting)") { try await $0.stop(id) } } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["ssh", id]) } } label: {
                    Label("SSH", systemImage: "terminal")
                }
                .disabled(state.cliPath == nil)
                .help(state.cliPath == nil ? "Install the boat CLI to use SSH" : "Open an SSH session in Terminal")
            }
            Menu {
                SandboxQuickActions(id: id)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 36)
        }
    }
}

struct OverviewTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var detail: JSON?
    @VState private var usage: JSON?
    @VState private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Machine") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            KV(key: "State", value: detail?.first("state", "status")?.string)
                            KV(key: "Type", value: detail?.first("machineType", "type")?.string)
                            KV(key: "IP", value: detail?.first("machineIp", "ip")?.string, mono: true)
                            KV(key: "Environment", value: detail?.first("environment", "environmentName")?.string)
                            KV(key: "Created", value: detail?.first("createdAt")?.string.map { relative($0) })
                            KV(key: "Auto-stop", value: ttlText)
                            KV(key: "Snapshot", value: detail?.first("snapshotId")?.string, mono: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Usage") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            KV(key: "Machine time", value: usage?.first("seconds")?.double.map { durationText($0) })
                            KV(key: "Cost", value: usage?.first("dollars")?.double.map { String(format: "$%.3f", $0) })
                            KV(key: "Metering", value: usage?.first("running")?.bool.map { $0 ? "running" : "idle" })
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                GroupBox("Quick settings") {
                    HStack {
                        Button("Rename…") {
                            if let n = promptText("Rename sandbox", default: detail?["name"]?.string ?? "") {
                                Task { await state.run("Renamed") { try await $0.updateSandbox(id, ["name": .string(n)]) }; await load() }
                            }
                        }
                        Button("Extend +1h") { Task { await extend(3600) } }
                        Button("Extend +4h") { Task { await extend(4 * 3600) } }
                        Button("No auto-stop") {
                            Task { await state.run("Auto-stop disabled") { try await $0.updateSandbox(id, ["ttlSeconds": 0, "noAutoStop": true]) }; await load() }
                        }
                        Button("Save named snapshot…") {
                            if let n = promptText("Snapshot name", "Named snapshots can seed new sandboxes (boat new --from NAME).") {
                                Task { await state.run("Saving snapshot \(n)", refresh: false) { try await $0.saveNamedSnapshot(sandboxId: id, name: n) } }
                            }
                        }
                        Button("Download artifacts") { Task { await downloadArtifacts() } }
                    }
                    .padding(6)
                }
                GroupBox("All fields") {
                    JSONGrid(json: detail ?? .null).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
            .padding()
        }
        .toolbar { ToolbarItem { RawJSONButton(json: detail) } }
        .task { await load() }
    }

    var ttlText: String? {
        guard let t = detail?.first("ttlSeconds")?.double else { return detail?["noAutoStop"]?.bool == true ? "never" : nil }
        return t <= 0 ? "never" : durationText(t)
    }

    func load() async {
        do {
            detail = try await state.api.sandbox(id)
            error = nil
        } catch { self.error = error.localizedDescription }
        usage = try? await state.api.usage(id)
    }

    func extend(_ secs: Double) async {
        let cur = detail?["ttlSeconds"]?.double ?? 3600
        await state.run("Extended") { try await $0.updateSandbox(id, ["ttlSeconds": .number(cur + secs)]) }
        await load()
    }

    func downloadArtifacts() async {
        do {
            let (data, resp) = try await state.api.artifacts(id)
            let panel = NSSavePanel()
            let fname = resp.suggestedFilename ?? "\(id)-artifacts.tar"
            panel.nameFieldStringValue = fname
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url); state.toast("Saved \(url.lastPathComponent)") }
        } catch { state.toast("Artifacts failed — \(error.localizedDescription)", error: true) }
    }
}

func durationText(_ s: Double) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.day, .hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.maximumUnitCount = 2
    return f.string(from: s) ?? "\(Int(s))s"
}

struct AccessTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var port = "3000"
    @VState private var title = ""
    @VState private var isPublic = false
    @VState private var hosted: [HostedURL] = []
    @VState private var fwdRemote = "3000"
    @VState private var fwdLocal = ""
    @VState private var forwards: [(String, () -> Void)] = []
    @VState private var sshKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Host a port on a URL") {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Port", text: $port).frame(width: 80)
                            TextField("Title (optional)", text: $title)
                            Toggle("Public", isOn: $isPublic)
                            Button("Create URL") { Task { await host() } }.buttonStyle(.borderedProminent)
                        }
                        ForEach(hosted) { h in
                            let url = h.url
                            HStack {
                                Text(":\(h.port)").monospaced()
                                Link(url, destination: URL(string: url) ?? URL(string: "https://boat.dev")!).lineLimit(1)
                                Spacer()
                                Button { copyToClipboard(url) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                            }
                        }
                    }.padding(6)
                }
                GroupBox("Forward a port to this Mac (boat forward)") {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Remote port", text: $fwdRemote).frame(width: 110)
                            TextField("Local port (same)", text: $fwdLocal).frame(width: 130)
                            Button("Start forwarding") { startForward() }.disabled(state.cliPath == nil)
                        }
                        ForEach(forwards.indices, id: \.self) { i in
                            HStack {
                                Text(forwards[i].0).monospaced()
                                Spacer()
                                Button("Stop") { forwards[i].1(); forwards.remove(at: i) }
                            }
                        }
                        if state.cliPath == nil { Text("Requires the boat CLI.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(6)
                }
                GroupBox("Desktop (GUI in the browser)") {
                    HStack {
                        Button("Open desktop") { Task { await openDesktop(vnc: false) } }
                        Button("Open noVNC") { Task { await openDesktop(vnc: true) } }
                    }.padding(6)
                }
                GroupBox("SSH") {
                    VStack(alignment: .leading) {
                        HStack {
                            Button("SSH in Terminal") { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["ssh", id]) } }
                                .disabled(state.cliPath == nil)
                            Button("Copy `boat ssh` command") { copyToClipboard("boat ssh \(id)") }
                            Button("Use ~/.ssh/id_ed25519.pub") {
                                let p = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/id_ed25519.pub")
                                sshKey = (try? String(contentsOf: p)) ?? (try? String(contentsOf: p.deletingLastPathComponent().appendingPathComponent("id_rsa.pub"))) ?? ""
                            }
                        }
                        HStack {
                            TextField("ssh-ed25519 AAAA… public key", text: $sshKey)
                            Button("Add key") {
                                Task { await state.run("SSH key added", refresh: false) { try await $0.addSSHKey(id, publicKey: sshKey.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                            }.disabled(sshKey.isEmpty)
                        }
                    }.padding(6)
                }
            }
            .padding()
        }
        .onDisappear { forwards.forEach { $0.1() } }
    }

    func host() async {
        guard let p = Int(port) else { return }
        if let r = await state.run("Port \(p) hosted", refresh: false, { try await $0.host(id, port: p, title: title, isPublic: isPublic) }),
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
        let label = "localhost:\(fwdLocal.isEmpty ? fwdRemote : fwdLocal) → sandbox:\(fwdRemote)"
        forwards.append((label, stop))
        Task { for await chunk in stream { if chunk.contains("[exit") { state.toast("Forward ended: \(label)", error: true) } } }
    }
}

struct SandboxSnapshotsTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var snaps: [Record] = []
    @VState private var sel: Set<Record.ID> = []
    @VState private var error: String?
    var body: some View {
        VStack {
            if let error { Text(error).foregroundStyle(.red).padding() }
            Table(snaps, selection: $sel) {
                TableColumn("ID") { s in Text(s.id).monospaced().textSelection(.enabled) }
                TableColumn("Status") { s in Text(s["status", "state"] ?? "—") }
                TableColumn("Size") { s in Text(byteString(s.json.first("sizeBytes", "size")?.double)) }
                TableColumn("Created") { s in Text(relative(s["createdAt"])) }
            }
            .contextMenu(forSelectionType: Record.ID.self) { ids in
                Button("Copy ID") { if let i = ids.first { copyToClipboard(i) } }
                Button("Delete…", role: .destructive) {
                    guard let i = ids.first, confirm("Delete snapshot \(i)?", "This can't be undone.") else { return }
                    Task { await state.run("Snapshot deleted", refresh: false) { try await $0.deleteSnapshot(i) }; await load() }
                }
            }
        }
        .task { await load() }
    }
    func load() async {
        do { snaps = try await state.api.sandboxSnapshots(id); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct HostedURL: Identifiable {
    let id = UUID()
    let port: Int
    let url: String
}
