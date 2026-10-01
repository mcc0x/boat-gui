import SwiftUI

// MARK: - Snapshots

struct SnapshotsView: View {
    @EnvironmentObject var state: AppState
    @VState private var scope = "named"
    @VState private var all: [Record] = []
    @VState private var sel: Set<Record.ID> = []
    @VState private var error: String?
    @VState private var tree: JSON?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $scope) {
                Text("Named snapshots").tag("named")
                Text("All snapshots").tag("all")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320).padding(8)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if scope == "named" {
                Table(state.namedSnapshots, selection: $sel) {
                    TableColumn("Name") { s in Text(s.displayName).font(.body.weight(.medium)) }
                    TableColumn("Status") { s in Text(s["status", "state"] ?? "—") }
                    TableColumn("From sandbox") { s in Text(s["sandboxId"] ?? "—").monospaced() }
                    TableColumn("Size") { s in Text(byteString(s.json.first("sizeBytes", "size")?.double)) }
                    TableColumn("Created") { s in Text(relative(s["createdAt"])) }
                }
                .contextMenu(forSelectionType: Record.ID.self) { ids in
                    if let i = ids.first, let s = state.namedSnapshots.first(where: { $0.id == i }) {
                        let name = s["name"] ?? i
                        Button("Launch sandbox from \(name)") {
                            Task { await state.run("Launching from \(name)") { try await $0.createSandbox(["from": .string(name), "type": "default", "ttlSeconds": 3600]) } }
                        }
                        Button("Pull to Mac (boat snapshot pull)…") { pull(name) }.disabled(state.cliPath == nil)
                        Button("Copy name") { copyToClipboard(name) }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            guard confirm("Delete named snapshot \(name)?", "") else { return }
                            Task { await state.runOrCLI("Deleted \(name)", cli: ["snapshot", "rm", name]) { try await $0.deleteNamedSnapshot(name) }; await reload() }
                        }
                    }
                }
            } else {
                HSplitView {
                    Table(all, selection: $sel) {
                        TableColumn("ID") { s in Text(s.id).monospaced() }
                        TableColumn("Sandbox") { s in Text(s["sandboxId"] ?? "—").monospaced() }
                        TableColumn("Status") { s in Text(s["status"] ?? "—") }
                        TableColumn("Size") { s in Text(byteString(s.json.first("sizeBytes", "size")?.double)) }
                        TableColumn("Created") { s in Text(relative(s["createdAt"])) }
                    }
                    .contextMenu(forSelectionType: Record.ID.self) { ids in
                        if let i = ids.first {
                            Button("Show file tree") { Task { tree = try? await state.api.snapshotTree(i) } }
                            Button("Copy ID") { copyToClipboard(i) }
                            Button("Delete…", role: .destructive) {
                                guard confirm("Delete snapshot \(i)?", "Permanent.") else { return }
                                Task { await state.run("Snapshot deleted", refresh: false) { try await $0.deleteSnapshot(i) }; await reload() }
                            }
                        }
                    }
                    if let tree {
                        ScrollView { Text(treeText(tree)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding() }
                            .frame(minWidth: 260)
                    }
                }
            }
        }
        .navigationTitle("Snapshots")
        .toolbar { Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task { await reload() }
        .onChange(of: scope) { _ in Task { await reload() } }
    }

    func treeText(_ j: JSON) -> String {
        let items = j.list("entries", "files", "tree")
        if items.isEmpty { return j.pretty }
        return items.map { e in
            let p = e.first("path", "name")?.string ?? e.compact
            let sz = e.first("size", "sizeBytes")?.double.map { "  " + byteString($0) } ?? ""
            return p + sz
        }.joined(separator: "\n")
    }

    func reload() async {
        do {
            if scope == "named" { state.namedSnapshots = try await state.api.namedSnapshots() }
            else { all = try await state.api.allSnapshots() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func pull(_ name: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Pull here"
        guard panel.runModal() == .OK, let url = panel.url, let cli = state.cliPath else { return }
        BoatCLI.openInTerminal(cli, ["snapshot", "pull", name, "--output", url.path])
    }
}

// MARK: - Webhooks

struct WebhooksView: View {
    @EnvironmentObject var state: AppState
    @VState private var hooks: [Record] = []
    @VState private var sel: Set<Record.ID> = []
    @VState private var url = ""
    @VState private var events: Set<String> = ["sandbox.ready", "sandbox.error"]
    @VState private var error: String?
    let allEvents = ["sandbox.ready", "sandbox.error", "sandbox.archived", "sandbox.hydrated"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox("New webhook") {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("https://example.com/boat-hook", text: $url)
                        Button("Create") { Task { await create() } }.buttonStyle(.borderedProminent).disabled(url.isEmpty)
                    }
                    HStack {
                        ForEach(allEvents, id: \.self) { e in
                            Toggle(e, isOn: Binding(get: { events.contains(e) }, set: { if $0 { events.insert(e) } else { events.remove(e) } }))
                                .toggleStyle(.checkbox)
                        }
                    }
                }.padding(6)
            }
            .padding()
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal) }
            Table(hooks, selection: $sel) {
                TableColumn("URL") { h in Text(h["url"] ?? "—") }
                TableColumn("Events") { h in Text((h.json["events"]?.array ?? []).compactMap { $0.string }.joined(separator: ", ")) }
                TableColumn("Enabled") { h in Text(h.json["enabled"]?.bool.map { $0 ? "yes" : "no" } ?? "—") }
                TableColumn("ID") { h in Text(h.id).monospaced() }
            }
            .contextMenu(forSelectionType: Record.ID.self) { ids in
                if let i = ids.first {
                    let h = hooks.first { $0.id == i }
                    Button(h?.json["enabled"]?.bool == false ? "Enable" : "Disable") {
                        let en = !(h?.json["enabled"]?.bool ?? true)
                        Task { await state.run("Updated", refresh: false) { try await $0.updateWebhook(i, ["enabled": .bool(en)]) }; await reload() }
                    }
                    Button("Rotate signing secret") {
                        Task {
                            if let r = await state.run("Secret rotated", refresh: false, { try await $0.rotateWebhook(i) }),
                               let s = r.first("secret", "signingSecret")?.string ?? r["webhook"]?.first("secret", "signingSecret")?.string {
                                showSecret("New signing secret", s)
                            }
                        }
                    }
                    Button("Delete…", role: .destructive) {
                        guard confirm("Delete webhook?", h?["url"] ?? i) else { return }
                        Task { await state.runOrCLI("Webhook deleted", cli: ["webhook", "remove", i]) { try await $0.deleteWebhook(i) }; await reload() }
                    }
                }
            }
        }
        .navigationTitle("Webhooks")
        .toolbar { Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task { await reload() }
    }

    func reload() async {
        do { hooks = try await state.api.webhooks(); error = nil } catch { self.error = error.localizedDescription }
    }

    func create() async {
        let ev = allEvents.filter { events.contains($0) }
        if let r = await state.run("Webhook created", refresh: false, { try await $0.createWebhook(url: url, events: ev) }) {
            if let s = r.first("secret", "signingSecret")?.string ?? r["webhook"]?.first("secret", "signingSecret")?.string {
                showSecret("Webhook signing secret", s)
            }
            url = ""
        }
        await reload()
    }
}

// MARK: - API keys

struct APIKeysView: View {
    @EnvironmentObject var state: AppState
    @VState private var keys: [Record] = []
    @VState private var sel: Set<Record.ID> = []
    @VState private var error: String?
    @VState private var name = ""
    @VState private var preset = "full-sandbox"
    @VState private var ttlDays = ""
    @VState private var sandbox = ""
    @VState private var envName = ""
    @VState private var usage: JSON?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox("Create scoped key (via boat CLI)") {
                HStack {
                    TextField("Name", text: $name).frame(width: 160)
                    Picker("Preset", selection: $preset) {
                        ForEach(["read-only", "full-sandbox", "ci", "admin"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 200)
                    TextField("TTL days", text: $ttlDays).frame(width: 70)
                    TextField("Only sandbox (id)", text: $sandbox).frame(width: 140)
                    TextField("Only env", text: $envName).frame(width: 100)
                    Button("Create") { Task { await create() } }.buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty || state.cliPath == nil)
                }.padding(6)
            }
            .padding()
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal) }
            HSplitView {
                Table(keys, selection: $sel) {
                    TableColumn("Name") { k in Text(k.displayName) }
                    TableColumn("Prefix") { k in Text(k["prefix"] ?? "—").monospaced() }
                    TableColumn("Scope") { k in Text(k["preset", "scope"] ?? (k.json["actions"]?.array?.compactMap { $0.string }.joined(separator: ",") ?? "—")).lineLimit(1) }
                    TableColumn("Expires") { k in Text(k["expiresAt", "expiry"].map { relative($0) } ?? "never") }
                    TableColumn("Last used") { k in Text(relative(k["lastUsedAt"])) }
                }
                .contextMenu(forSelectionType: Record.ID.self) { ids in
                    if let i = ids.first {
                        Button("Usage (30 days)") { Task { usage = try? await state.api.apiKeyUsage(i) } }
                        Button("Rotate…") {
                            guard confirm("Rotate key?", "The old secret stops working.", destructive: "Rotate") else { return }
                            Task {
                                if let r = await state.cli("Key rotated", ["api-key", "rotate", i, "--json"]) { revealSecret(r) }
                                await reload()
                            }
                        }
                        Button("Revoke…", role: .destructive) {
                            guard confirm("Revoke key?", "Anything using it will lose access.", destructive: "Revoke") else { return }
                            Task { await state.cli("Key revoked", ["api-key", "revoke", i]); await reload() }
                        }
                    }
                }
                if let usage {
                    ScrollView { JSONGrid(json: usage).padding() }.frame(minWidth: 260)
                }
            }
        }
        .navigationTitle("API Keys")
        .toolbar { Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task { await reload() }
    }

    func reload() async {
        do {
            keys = try await state.api.apiKeys()
            if keys.isEmpty, let cli = state.cliPath {
                let r = await BoatCLI.run(cli, ["api-key", "list", "--all", "--json"])
                keys = (r.json?.list("apiKeys", "keys") ?? []).map(Record.init)
            }
            error = keys.isEmpty ? "No keys visible (restricted keys can't list keys)." : nil
        } catch { self.error = error.localizedDescription }
    }

    func create() async {
        var args = ["api-key", "create", name, "--preset", preset, "--json"]
        if !ttlDays.isEmpty { args += ["--ttl", ttlDays] }
        if !sandbox.isEmpty { args += ["--sandbox", sandbox] }
        if !envName.isEmpty { args += ["--env", envName] }
        if let r = await state.cli("Key created", args), r.exitCode == 0 { revealSecret(r); name = "" }
        await reload()
    }

    func revealSecret(_ r: CLIResult) {
        let j = r.json
        let s = j?.first("key", "secret", "token")?.string ?? j?["apiKey"]?.first("key", "secret", "token")?.string
        showSecret("API key", s ?? r.stdout)
    }
}

// MARK: - Account

struct AccountView: View {
    @EnvironmentObject var state: AppState
    @VState private var orgs: JSON?
    @VState private var retention: JSON?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    GroupBox("You") {
                        JSONGrid(json: state.me?["user"] ?? state.me ?? .null).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Balance") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let h = state.limits?.first("creditBalanceHours")?.double {
                                Text(String(format: "%.1f hours", h)).font(.system(size: 30, weight: .bold, design: .rounded))
                            }
                            if let d = state.limits?.first("packBalanceDollars")?.double {
                                Text(String(format: "$%.2f in credit packs", d)).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Can start sandboxes:")
                                Text(state.limits?["canStart"]?.bool == false ? "No" : "Yes").bold()
                            }
                            if let c = state.limits?["concurrency"] {
                                Text("Running \(c["running"]?.string ?? "?") of \(c["limit"]?.string ?? "?") concurrent")
                                ProgressView(value: c["running"]?.double ?? 0, total: max(1, c["limit"]?.double ?? 1))
                            }
                            Link("Pricing & plans", destination: URL(string: "https://boat.dev/pricing")!)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                if let starts = state.limits?["starts"]?.object {
                    GroupBox("Start rate limits") {
                        HStack(spacing: 24) {
                            ForEach(starts.keys.sorted(), id: \.self) { k in
                                VStack {
                                    Text(k).font(.caption).foregroundStyle(.secondary)
                                    Text("\(starts[k]?["remaining"]?.string ?? "?")/\(starts[k]?["limit"]?.string ?? "?")").font(.title3.monospacedDigit())
                                }
                            }
                        }.padding(6)
                    }
                }
                GroupBox("Organizations & wallets") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orgs?.list("orgs", "organizations") ?? [], id: \.self) { o in
                            let name = o.first("name", "slug", "id")?.string ?? "?"
                            HStack {
                                Image(systemName: o["active"]?.bool == true ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(o["active"]?.bool == true ? .green : .secondary)
                                Text(name)
                                if let r = o["role"]?.string { Text(r).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Use this wallet") {
                                    Task { await switchOrg(name: name, id: o["id"]?.string ?? name) }
                                }
                            }
                        }
                        HStack {
                            Button("Switch to personal") { Task { await state.cli("Switched to personal", ["org", "switch", "personal"]); orgs = try? await state.api.orgs() } }
                            Button("Create org…") {
                                guard let n = promptText("New organization", ok: "Create") else { return }
                                Task { await state.cli("Org created", ["org", "create", n]); orgs = try? await state.api.orgs() }
                            }
                            Button("Invite member…") {
                                guard let e = promptText("Invite by email", ok: "Invite") else { return }
                                Task { await state.cli("Invited \(e)", ["org", "invite", e]) }
                            }
                        }
                        .disabled(state.cliPath == nil)
                    }.padding(6)
                }
                GroupBox("Privacy") {
                    HStack {
                        let on = retention?.first("enabled", "zeroDataRetention")?.bool ?? false
                        Toggle("Zero data retention", isOn: Binding(get: { on }, set: { v in
                            Task { await state.run("Retention updated", refresh: false) { try await $0.setDataRetention(v) }; retention = try? await state.api.dataRetention() }
                        }))
                        Spacer()
                        RawJSONButton(json: retention)
                    }.padding(6)
                }
                GroupBox("Raw limits") { JSONGrid(json: state.limits ?? .null).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
            }
            .padding()
        }
        .navigationTitle("Account & Billing")
        .toolbar { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task { await load() }
    }

    func switchOrg(name: String, id: String) async {
        let body: JSON = .object(["org": .string(name), "orgId": .string(id)])
        let op: (BoatAPI) async throws -> JSON = { api in try await api.call("PATCH", "/orgs/active", body: body) }
        await state.runOrCLI("Switched to \(name)", cli: ["org", "switch", name], op)
        orgs = try? await state.api.orgs()
        await state.refreshAll()
    }

    func load() async {
        await state.refreshAll()
        orgs = try? await state.api.orgs()
        retention = try? await state.api.dataRetention()
    }
}

// MARK: - CLI console

struct CLIConsoleView: View {
    @EnvironmentObject var state: AppState
    @VState private var args = ""
    @VState private var output = ""
    @VState private var running = false
    @VState private var stopper: (() -> Void)?

    let presets = ["status", "list", "limits", "env list", "snapshot list", "webhook list", "api-key list",
                   "conversations", "org list", "self-update"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.cliPath ?? "boat CLI not found").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Menu("Quick commands") { ForEach(presets, id: \.self) { p in Button("boat \(p)") { args = p; run() } } }
                    .frame(width: 160)
                Button("Open Terminal with boat") { if let p = state.cliPath { BoatCLI.openInTerminal(p, args.isEmpty ? ["status"] : split(args)) } }
                Button("Clear") { output = "" }
            }
            .controlSize(.small).padding(8)
            LogView(text: output)
            Divider()
            HStack {
                Text("boat").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                TextField("list --json", text: $args).textFieldStyle(.plain).font(.system(.body, design: .monospaced))
                    .onSubmit { run() }
                if running { Button("Stop") { stopper?(); running = false } }
                else { Button("Run") { run() }.keyboardShortcut(.defaultAction) }
            }
            .padding(10)
        }
        .navigationTitle("CLI Console")
    }

    func split(_ s: String) -> [String] {
        var out: [String] = [], cur = "", q: Character? = nil
        for ch in s {
            if let qq = q { if ch == qq { q = nil } else { cur.append(ch) } }
            else if ch == "\"" || ch == "'" { q = ch }
            else if ch == " " { if !cur.isEmpty { out.append(cur); cur = "" } }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    func run() {
        guard let cli = state.cliPath else { output += "boat CLI not found. Install: curl -fsSL https://boat.dev/install | sh\n"; return }
        let a = split(args)
        let interactive = ["ssh", "login", "onboard"].contains(a.first ?? "")
        if interactive { BoatCLI.openInTerminal(cli, a); output += "→ opened `boat \(args)` in Terminal (interactive)\n"; return }
        output += "\n$ boat \(args)\n"
        running = true
        let (stream, stop) = BoatCLI.stream(cli, a + ["--no-update"])
        stopper = stop
        Task {
            for await chunk in stream { output += chunk }
            running = false
            if a.first != "list" { await state.refreshSandboxes(silent: true) }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @VState private var key = ""
    var body: some View {
        Form {
            SecureField("API key", text: $key)
                .onAppear { key = state.apiKey }
            HStack {
                Button("Save key") { state.apiKey = key; Task { await state.refreshAll() } }
                Button("Sign out") { key = ""; state.apiKey = "" }
            }
            TextField("API base URL", text: $state.apiURL)
            TextField("Organization (optional)", text: $state.org)
            TextField("boat CLI path (auto if empty)", text: $state.cliPathOverride)
            HStack {
                Text("Detected: \(state.cliPath ?? "not found")").font(.caption).foregroundStyle(.secondary)
                Button("Re-detect") { state.relocateCLI() }
            }
            Stepper("Refresh every \(Int(state.refreshSeconds))s", value: $state.refreshSeconds, in: 3...300, step: 1)
            Toggle("Notify on sandbox state changes", isOn: $state.notifyOnStateChange)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sailboat.fill")
                Text("Boat").font(.headline)
                Spacer()
                if let h = state.limits?.first("creditBalanceHours")?.double {
                    Text(String(format: "%.1f h", h)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if state.sandboxes.isEmpty {
                Text(state.hasKey ? "No sandboxes" : "Add an API key in the app").foregroundStyle(.secondary)
            }
            ForEach(state.sandboxes.prefix(12)) { s in
                HStack {
                    Circle().fill(s.stateColor).frame(width: 8, height: 8)
                    Text(s.displayName).lineLimit(1)
                    Spacer()
                    Text(s.state).font(.caption).foregroundStyle(.secondary)
                    Menu { SandboxQuickActions(id: s.id) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 24)
                    Button {
                        state.section = .sandboxes; state.selectedSandbox = s.id
                        openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                    } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(.borderless)
                }
            }
            Divider()
            HStack {
                Button("New sandbox") {
                    state.showNewSandbox = true; state.section = .sandboxes
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quick launch") {
                    Task { await state.run("Sandbox launching") { try await $0.createSandbox(["type": "default", "ttlSeconds": 3600]) } }
                }
                Spacer()
                Button { Task { await state.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 360)
    }
}
