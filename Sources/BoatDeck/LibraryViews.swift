import SwiftUI

// MARK: - Snapshots

struct SnapshotsView: View {
    @EnvironmentObject var state: AppState
    @VState private var scope = "named"
    @VState private var all: [Record] = []
    @VState private var error: String?
    @VState private var loaded = false
    @VState private var tree: (String, JSON)?
    @VState private var search = ""

    var body: some View {
        Page {
            PageHeader(title: "Snapshots", subtitle: "Frozen disk images. Named snapshots seed new sandboxes with `--from`.") {
                IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await reload() } }
            }
            .appear()
            HStack {
                PillPicker(options: [PillOption(value: "named", label: "Named", icon: "tag"),
                                     PillOption(value: "all", label: "All snapshots", icon: "square.stack.3d.up")], selection: $scope)
                Spacer()
                SearchField(text: $search, prompt: "Filter").frame(width: 240)
            }
            if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red) }

            if !loaded {
                VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in SkeletonRow() } }
            } else if scope == "named" {
                let items = state.namedSnapshots.filter { search.isEmpty || $0.displayName.lowercased().contains(search.lowercased()) }
                if items.isEmpty {
                    EmptyStateView(icon: "tag", title: "No named snapshots",
                                   message: "Save one from any sandbox (⋯ › Save Named Snapshot) to reuse a fully set-up machine.")
                        .frame(height: 360)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                            NamedSnapshotCard(s: s, reload: reload).appear(delay: 0.03 * Double(i))
                        }
                    }
                }
            } else {
                let items = all.filter { search.isEmpty || $0.id.contains(search) || ($0["sandboxId"] ?? "").contains(search) }
                AdaptiveStack {
                    VStack(spacing: 0) {
                        if items.isEmpty { Text("No snapshots.").font(.bdSmall).foregroundStyle(BD.text3).padding() }
                        ForEach(items) { s in
                            HStack(spacing: 12) {
                                Image(systemName: "camera.aperture").foregroundStyle(BD.text2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.id).font(.bdMono).foregroundStyle(BD.text).lineLimit(1)
                                    Text([s["kind"].map { $0 == "base" ? "full image" : $0 }, "from \(s["sandboxId"] ?? "—")", s.json["fileCount"]?.int.map { "\($0) files" }, relative(s["createdAt"])].compactMap { $0 }.joined(separator: " · ")).font(.bdSmall).foregroundStyle(BD.text3)
                                }
                                Spacer()
                                Text(byteString(s.json.first("sizeBytes", "size")?.double)).font(.bdSmall.monospacedDigit()).foregroundStyle(BD.text2)
                                Button("Files") { Task { if let t = try? await state.api.snapshotTree(s.id) { withAnimation(BD.spring) { tree = (s.id, t) } } } }
                                    .bdButton(.ghost, .small)
                                IconButton(icon: "trash", size: 24) {
                                    guard confirm("Delete snapshot \(s.id)?", "Permanent.") else { return }
                                    Task { await state.run("Snapshot deleted", refresh: false) { try await $0.deleteSnapshot(s.id) }; await reload() }
                                }
                            }
                            .listRow(divider: s.id != items.last?.id)
                        }
                    }
                    if let tree {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Eyebrow(text: "Files in \(tree.0)")
                                Spacer()
                                IconButton(icon: "xmark", size: 22) { withAnimation(BD.spring) { self.tree = nil } }
                            }
                            ScrollView { Text(treeText(tree.1)).font(.bdMonoSmall).foregroundStyle(BD.text2).textSelection(.enabled) }
                                .frame(maxHeight: 520)
                        }
                        .frame(maxWidth: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .task { await reload() }
        .onChange(of: scope) { _, _ in Task { await reload() } }
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
            if scope == "named" { let n = try await state.api.namedSnapshots(); withAnimation(BD.spring) { state.namedSnapshots = n } }
            else { let a = try await state.api.allSnapshots(); withAnimation(BD.spring) { all = a } }
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct NamedSnapshotCard: View {
    let s: Record
    let reload: () async -> Void
    @EnvironmentObject var state: AppState
    var name: String { s["name"] ?? s.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BD.surfaceHi)
                    Image(systemName: "tag.fill").font(.system(size: 14)).foregroundStyle(BD.text)
                }
                .frame(width: 36, height: 36)
                Spacer()
                StateBadge(state: s["status", "state"] ?? "ready")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(BD.text)
                Text("from \(s["sandboxId"] ?? "—") · \(relative(s["createdAt"]))").font(.bdSmall).foregroundStyle(BD.text3).lineLimit(1)
            }
            HStack(spacing: 6) {
                Chip(text: byteString(s.json.first("sizeBytes", "size")?.double), icon: "internaldrive")
                Spacer()
            }
            Hairline()
            HStack {
                Button {
                    Task { await state.run("Launching from \(name)") { try await $0.createSandbox(["from": .string(name), "type": .string(state.defaultType), "ttlSeconds": .number(state.defaultTTLHours * 3600)]) } }
                } label: { Label("Launch", systemImage: "play.fill") }
                .bdButton(.primary, .small)
                Spacer()
                Menu {
                    Button("Copy name") { copyToClipboard(name) }
                    Button("Pull to Mac…") { pull() }.disabled(state.cliPath == nil)
                    Divider()
                    Button("Delete…", role: .destructive) {
                        guard confirm("Delete named snapshot \(name)?", "") else { return }
                        Task { await state.runAction("Deleted \(name)") { try await $0.deleteNamedSnapshot(name) }; await reload() }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .glassCard(interactive: true)
        .hoverLift()
    }

    func pull() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Pull here"
        guard panel.runModal() == .OK, let url = panel.url, state.cliPath != nil else { return }
        state.openCLI(["snapshot", "pull", name, "--output", url.path])
    }
}

// MARK: - Webhooks

struct WebhooksView: View {
    @EnvironmentObject var state: AppState
    @VState private var hooks: [Record] = []
    @VState private var url = ""
    @VState private var events: Set<String> = ["sandbox.ready", "sandbox.error"]
    @VState private var error: String?
    @VState private var loaded = false
    let allEvents = ["sandbox.ready", "sandbox.error", "sandbox.archived", "sandbox.hydrated"]

    var body: some View {
        Page {
            PageHeader(title: "Webhooks", subtitle: "Get a signed POST when sandboxes change state.") {
                IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await reload() } }
            }
            .appear()

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "New endpoint")
                HStack {
                    Field(placeholder: "https://example.com/hooks/boat", text: $url, mono: true)
                    Button { Task { await create() } } label: { Label("Create", systemImage: "plus") }
                        .bdButton(.primary).disabled(url.isEmpty || events.isEmpty)
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(allEvents, id: \.self) { e in
                        let on = events.contains(e)
                        Button {
                            withAnimation(BD.snappy) { if on { events.remove(e) } else { events.insert(e) } }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                                Text(e).font(.bdMonoSmall)
                            }
                            .foregroundStyle(on ? BD.text : BD.text3)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(on ? BD.surfaceHi : BD.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? BD.strokeHi : BD.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .appear(delay: 0.04)

            Hairline()

            if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red) }
            if !loaded {
                VStack(spacing: 0) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
            } else if hooks.isEmpty {
                EmptyStateView(icon: "antenna.radiowaves.left.and.right", title: "No webhooks",
                               message: "Add an endpoint above to be notified when a sandbox is ready, errors, archives or hydrates.")
                    .frame(height: 320)
            } else {
                VStack(spacing: 0) {
                    ForEach(hooks) { h in WebhookRow(h: h, reload: reload); Hairline() }
                }
                .appear(delay: 0.08)
            }
        }
        .task { await reload() }
    }

    func reload() async {
        do { let h = try await state.api.webhooks(); withAnimation(BD.spring) { hooks = h }; error = nil } catch { self.error = error.localizedDescription }
        loaded = true
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

struct WebhookRow: View {
    let h: Record
    let reload: () async -> Void
    @EnvironmentObject var state: AppState
    var enabled: Bool { h.json["enabled"]?.bool ?? true }
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: enabled ? "ready" : "archived", size: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(h["url"] ?? "—").font(.bdMono).foregroundStyle(BD.text).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    ForEach((h.json["events"]?.array ?? []).compactMap { $0.string }, id: \.self) { Chip(text: $0, mono: true) }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { enabled }, set: { v in
                Task { await state.run(v ? "Enabled" : "Disabled", refresh: false) { try await $0.updateWebhook(h.id, ["enabled": .bool(v)]) }; await reload() }
            }))
            .toggleStyle(.switch).labelsHidden().controlSize(.small)
            Button("Rotate secret") {
                Task {
                    if let r = await state.run("Secret rotated", refresh: false, { try await $0.rotateWebhook(h.id) }),
                       let s = r.first("secret", "signingSecret")?.string ?? r["webhook"]?.first("secret", "signingSecret")?.string {
                        showSecret("New signing secret", s)
                    }
                }
            }
            .bdButton(.ghost, .small)
            IconButton(icon: "trash", size: 26) {
                guard confirm("Delete webhook?", h["url"] ?? h.id) else { return }
                Task { await state.runAction("Webhook deleted") { try await $0.deleteWebhook(h.id) }; await reload() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - API keys

struct APIKeysView: View {
    @EnvironmentObject var state: AppState
    @VState private var keys: [Record] = []
    @VState private var error: String?
    @VState private var loaded = false
    @VState private var name = ""
    @VState private var preset = "full-sandbox"
    @VState private var ttlDays = ""
    @VState private var sandbox = ""
    @VState private var envName = ""
    @VState private var usage: (String, JSON)?

    let presets: [(String, String, String)] = [
        ("read-only", "Read-only", "eye"), ("full-sandbox", "Full sandbox", "shippingbox"),
        ("ci", "CI", "gearshape.2"), ("admin", "Admin", "crown")]

    var body: some View {
        Page {
            PageHeader(title: "API Keys", subtitle: "Scoped keys for scripts, CI and teammates. Secrets are shown once.") {
                IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await reload() } }
            }
            .appear()

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Create key")
                HStack(spacing: 10) {
                    ForEach(presets, id: \.0) { p in
                        let on = preset == p.0
                        Button { withAnimation(BD.snappy) { preset = p.0 } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: p.2).font(.system(size: 14))
                                Text(p.1).font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(on ? BD.text : BD.text2)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(on ? BD.surfaceHi : BD.surface, in: RoundedRectangle(cornerRadius: BD.r2, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: BD.r2, style: .continuous).strokeBorder(on ? BD.strokeHi : BD.stroke, lineWidth: on ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    Field(placeholder: "Key name", text: $name).frame(width: 200)
                    Field(placeholder: "TTL days", text: $ttlDays, mono: true).frame(width: 90)
                    Field(placeholder: "Only sandbox id", text: $sandbox, mono: true).frame(width: 160)
                    Field(placeholder: "Only env", text: $envName).frame(width: 120)
                    Button { Task { await create() } } label: { Label("Create", systemImage: "key.fill") }
                        .bdButton(.primary).disabled(name.isEmpty)
                }
                if state.cliPath == nil {
                    Label("Creating keys requires an admin API key. CLI account management is available in Console.", systemImage: "info.circle")
                        .font(.bdSmall).foregroundStyle(BD.text3)
                }
            }
            .appear(delay: 0.04)

            if let error { Text(error).font(.bdSmall).foregroundStyle(BD.text3) }
            AdaptiveStack {
                VStack(spacing: 0) {
                    if !loaded { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                    else if keys.isEmpty {
                        EmptyStateView(icon: "key", title: "No keys to show", message: "Restricted keys can't list other keys.").frame(height: 260)
                    }
                    ForEach(keys) { k in
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill").font(.system(size: 12)).foregroundStyle(BD.text2)
                                .frame(width: 30, height: 30).background(BD.surfaceHi, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(k.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(BD.text)
                                    if let p = k["keyPrefix", "prefix"] { Chip(text: p + "…" + (k["keyLastFour"] ?? ""), mono: true) }
                                    if k.json["expired"]?.bool == true { Chip(text: "expired", icon: "exclamationmark.triangle") }
                                    else if k.json["expiringSoon"]?.bool == true { Chip(text: "expiring soon", icon: "clock") }
                                }
                                Text([scopeText(k), k.json["usage"]?["requests"]?.int.map { "\($0) requests / 30d" }, k["expiresAt", "expiry"].map { "expires " + relative($0) }, k["lastUsedAt"].map { "used " + relative($0) }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.bdSmall).foregroundStyle(BD.text3)
                            }
                            Spacer(minLength: 8)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { keyActions(k) }
                                Menu { keyActions(k) } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                        }
                        .listRow(divider: k.id != keys.last?.id)
                    }
                }
                if let usage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Eyebrow(text: "30-day usage · \(usage.0)"); Spacer(); IconButton(icon: "xmark", size: 22) { withAnimation(BD.spring) { self.usage = nil } } }
                        JSONGrid(json: usage.1)
                    }
                    .frame(maxWidth: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .task { await reload() }
    }

    func reload() async {
        do {
            let k = try await state.api.apiKeys()
            withAnimation(BD.spring) { keys = k }
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    func create() async {
        var body: [String: JSON] = ["name": .string(name), "preset": .string(preset)]
        if let d = Int(ttlDays) { body["ttlDays"] = .number(Double(d)) }
        if !sandbox.isEmpty { body["sandboxId"] = .string(sandbox) }
        if !envName.isEmpty { body["environment"] = .string(envName) }
        if let r = await state.run("Key created", refresh: false, { try await $0.call("POST", "/api-keys/scoped", body: .object(body)) }) {
            if let s = r.first("key", "secret", "token")?.string ?? r["apiKey"]?.first("key", "secret", "token")?.string {
                showSecret("API key", s)
            } else {
                state.toast("Key created, but its secret was not returned. Check API Keys before trying again.", error: true)
            }
            name = ""
            await reload()
        }
    }

    @ViewBuilder func keyActions(_ k: Record) -> some View {
        Button("Usage") { Task { if let u = try? await state.api.apiKeyUsage(k.id) { withAnimation(BD.spring) { usage = (k.displayName, u) } } } }
            .bdButton(.ghost, .small)
        Button("Rotate") {
            guard confirm("Rotate key?", "The old secret stops working.", destructive: "Rotate") else { return }
            Task { if let r = await state.cli("Key rotated", ["api-key", "rotate", k.id, "--json"]), r.exitCode == 0 { revealSecret(r) }; await reload() }
        }
        .bdButton(.secondary, .small).disabled(state.cliPath == nil)
        Button("Revoke") {
            guard confirm("Revoke key?", "Anything using it will lose access.", destructive: "Revoke") else { return }
            Task { await state.cli("Key revoked", ["api-key", "revoke", k.id]); await reload() }
        }
        .bdButton(.danger, .small).disabled(state.cliPath == nil)
    }

    func scopeText(_ k: Record) -> String? {
        let acts = (k.json["scope"]?["actions"]?.array ?? []).compactMap { $0.string }
        if acts == ["*"] { return "full access" }
        if acts.isEmpty { return k["preset"] }
        return acts.count <= 3 ? acts.joined(separator: ", ") : "\(acts.count) actions"
    }

    func revealSecret(_ r: CLIResult) {
        let j = r.json
        let s = j?.first("key", "secret", "token")?.string ?? j?["apiKey"]?.first("key", "secret", "token")?.string
        showSecret("API key", s ?? r.stdout)
    }
}
