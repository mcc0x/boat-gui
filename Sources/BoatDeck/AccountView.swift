import SwiftUI

struct AccountView: View {
    @EnvironmentObject var state: AppState
    @VState private var orgs: JSON?
    @VState private var retention: JSON?

    var body: some View {
        Page {
            PageHeader(title: "Account", subtitle: "Balance, limits, organizations and privacy.") {
                HStack {
                    Link(destination: URL(string: "https://boat.dev/pricing")!) { Label("Plans & pricing", systemImage: "arrow.up.right") }
                        .buttonStyle(BDButtonStyle())
                    IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await load() } }
                }
            }
            .appear()

            AdaptiveStack(breakpoint: 820, spacing: 40) {
                profileCard.appear(delay: 0.03)
                balanceCard.appear(delay: 0.06)
            }

            Hairline()

            if let starts = state.limits?["starts"]?.object, !starts.isEmpty {
                limitsCard(starts).appear(delay: 0.09)
                Hairline()
            }

            orgsCard.appear(delay: 0.12)

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Privacy")
                let on = retention?.first("enabled", "zeroDataRetention")?.bool ?? false
                Toggle(isOn: Binding(get: { on }, set: { v in
                    Task { await state.run("Data retention updated", refresh: false) { try await $0.setDataRetention(v) }; retention = try? await state.api.dataRetention() }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zero data retention").font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text)
                        Text("Don't keep prompts, transcripts or outputs after a sandbox is deleted.").font(.bdSmall).foregroundStyle(BD.text3)
                    }
                }
                .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            .appear(delay: 0.15)
        }
        .task { await load() }
    }

    var profileCard: some View {
        let u = state.me?["user"] ?? state.me ?? .null
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(name: state.userName, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(u.first("name", "login")?.string ?? state.userName).font(.bdH2).foregroundStyle(BD.text)
                    Text(u.first("email")?.string ?? "").font(.bdBody).foregroundStyle(BD.text2)
                }
            }
            Hairline()
            KVRow(key: "Plan", value: u.first("accountPlan", "plan")?.string?.capitalized)
            KVRow(key: "Status", value: u.first("accountStatus", "status")?.string?.capitalized)
            KVRow(key: "Sign-in", value: u.first("connectionMethod")?.string?.capitalized)
            KVRow(key: "Account ID", value: u.first("id")?.string, copy: true)
            DisclosureGroup {
                JSONGrid(json: .object((u.object ?? [:]).filter { $0.value != .null }), skip: ["ok", "type"]).padding(.top, 6)
            } label: { Text("All fields").font(.bdSmall).foregroundStyle(BD.text3) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        
    }

    var balanceCard: some View {
        let hours = state.creditHours
        let running = state.concurrency.0
        let limit = state.concurrency.1 ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Balance")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hours.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 44, weight: .semibold, design: .rounded)).foregroundStyle(BD.text)
                    .contentTransition(.numericText())
                Text("hours of compute").font(.bdBody).foregroundStyle(BD.text2)
            }
            HStack(spacing: 18) {
                if let d = state.limits?.first("packBalanceDollars")?.double {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "$%.2f", d)).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(BD.text)
                        Text("credit packs").font(.bdSmall).foregroundStyle(BD.text3)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.limits?["canStart"]?.bool == false ? "Blocked" : "Yes").font(.system(size: 16, weight: .semibold)).foregroundStyle(state.limits?["canStart"]?.bool == false ? BD.red : BD.text)
                    Text("can start").font(.bdSmall).foregroundStyle(BD.text3)
                }
                Spacer()
                if limit > 0 {
                    RingGauge(value: running / limit, lineWidth: 7, color: BD.green).frame(width: 60, height: 60)
                        .overlay(VStack(spacing: 0) {
                            Text("\(Int(running))").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(BD.text)
                            Text("/\(Int(limit))").font(.system(size: 9)).foregroundStyle(BD.text3)
                        })
                }
            }
            if state.limits?["canStart"]?.bool == false {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(BD.amber)
                    Text("New sandboxes are blocked until you pick a plan or add credit.").font(.bdSmall).foregroundStyle(BD.text2)
                    Spacer(minLength: 0)
                    Link(destination: URL(string: "https://boat.dev/pricing")!) { Text("Choose plan") }.buttonStyle(BDButtonStyle(kind: .primary, size: .small))
                }
                .panel(padding: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        
    }

    func limitsCard(_ starts: [String: JSON]) -> some View {
        let order = ["minute", "hour", "day", "week", "month"]
        let keys = starts.keys.filter { starts[$0]?["limit"]?.double != nil }
            .sorted { (order.firstIndex(of: $0) ?? 9) < (order.firstIndex(of: $1) ?? 9) }
        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Sandbox start limits")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(keys, id: \.self) { k in
                    let lim = starts[k]?["limit"]?.double ?? 0
                    let rem = starts[k]?["remaining"]?.double ?? 0
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(rem))").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(BD.text)
                            Text("/ \(Int(lim))").font(.bdSmall).foregroundStyle(BD.text3)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(BD.surfaceHi)
                                Capsule().fill(BD.text).frame(width: g.size.width * (lim > 0 ? rem / lim : 0))
                            }
                        }
                        .frame(height: 5)
                        Text("left this \(k)").font(.bdSmall).foregroundStyle(BD.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
            }
            if starts.keys.contains(where: { starts[$0]?["limit"]?.double == nil }) {
                Text("No limit on longer windows.").font(.bdSmall).foregroundStyle(BD.text3)
            }
        }
        
    }

    var orgsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Organizations & wallets")
                Spacer()
                Button("Personal") { Task { await state.cli("Switched to personal", ["org", "switch", "personal"]); orgs = try? await state.api.orgs(); await state.refreshAll() } }
                    .bdButton(.ghost, .small).disabled(state.cliPath == nil)
                Button { newOrg() } label: { Label("New org", systemImage: "plus") }.bdButton(.secondary, .small).disabled(state.cliPath == nil)
                Button { invite() } label: { Label("Invite", systemImage: "person.badge.plus") }.bdButton(.secondary, .small).disabled(state.cliPath == nil)
            }
            let list = orgs?.list("orgs", "organizations") ?? []
            if list.isEmpty { Text("Only your personal wallet.").font(.bdSmall).foregroundStyle(BD.text3) }
            ForEach(list, id: \.self) { o in
                let name = o.first("name", "slug", "id")?.string ?? "?"
                let active = o["active"]?.bool == true
                HStack(spacing: 12) {
                    Avatar(name: name, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text)
                        Text(o["role"]?.string ?? "member").font(.bdSmall).foregroundStyle(BD.text3)
                    }
                    Spacer()
                    if active { Chip(text: "active", icon: "checkmark") }
                    else {
                        Button("Use wallet") { Task { await switchOrg(name: name, id: o["id"]?.string ?? name) } }.bdButton(.secondary, .small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        
    }

    func newOrg() {
        guard let n = promptText("New organization", ok: "Create") else { return }
        Task { await state.cli("Org created", ["org", "create", n]); orgs = try? await state.api.orgs() }
    }
    func invite() {
        guard let e = promptText("Invite by email", ok: "Invite") else { return }
        Task { await state.cli("Invited \(e)", ["org", "invite", e]) }
    }

    func switchOrg(name: String, id: String) async {
        let body: JSON = .object(["org": .string(name), "orgId": .string(id)])
        let op: (BoatAPI) async throws -> JSON = { api in try await api.call("PATCH", "/orgs/active", body: body) }
        await state.runAction("Switched to \(name)", op)
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
    @VState private var task: Task<Void, Never>?
    @VState private var stopper: (() -> Void)?

    let presets = ["status", "list", "limits", "env list", "snapshot list", "webhook list", "api-key list",
                   "conversations", "org list", "self-update", "--help"]

    var body: some View {
        Page {
            PageHeader(title: "Console", subtitle: state.cliPath != nil ? "Run commands using your Boat CLI login." : "The boat CLI isn't installed yet.") {
                HStack {
                    Menu {
                        ForEach(presets, id: \.self) { preset in
                            Button("boat \(preset)") { args = preset }
                        }
                    } label: { Label("Commands", systemImage: "terminal") }
                    .menuStyle(.borderlessButton).fixedSize().tint(BD.text2)
                    .help("Choose a command, then press Run")
                    Button { state.openCLI(args.isEmpty ? ["status"] : split(args)) } label: {
                        Label("Open in Terminal", systemImage: "arrow.up.forward.app")
                    }
                    .bdButton().disabled(state.cliPath == nil)
                    if state.cliPath == nil {
                        Button { BoatCLI.openInTerminal("/bin/zsh", ["-lc", "curl -fsSL https://boat.dev/install | sh"]) } label: {
                            Label("Install CLI", systemImage: "arrow.down.circle")
                        }
                        .bdButton(.primary)
                    }
                }
            }
            .appear()

            VStack(spacing: 0) {
                LogView(text: output.isEmpty ? "# Output of boat commands appears here.\n# Interactive commands (ssh, login) open in Terminal." : output)
                    .frame(minHeight: 380)
                Hairline()
                HStack(spacing: 8) {
                    Text("boat").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(BD.green)
                    TextField("", text: $args, prompt: Text("Enter a command…").foregroundColor(BD.text3))
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).foregroundColor(BD.text)
                        .onSubmit { run() }
                    Button("Clear") { output = "" }.bdButton(.ghost, .small)
                    if running {
                        Spinner(size: 12)
                        Button("Stop") { task?.cancel(); stopper?() }.bdButton(.danger, .small)
                    } else {
                        Button { run() } label: { Label("Run", systemImage: "return") }
                            .bdButton(.primary, .small)
                            .disabled(args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.cliPath == nil)
                    }
                }
                .padding(12)
            }
            .background(BD.bgRaised, in: RoundedRectangle(cornerRadius: BD.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BD.r2, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
            .appear(delay: 0.05)
        }
        .onDisappear { task?.cancel(); stopper?() }
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
        guard !running else { return }
        guard state.cliPath != nil else { output += "boat CLI not found. Install it in Settings › CLI.\n"; return }
        let a = split(args)
        if ["ssh", "login", "onboard"].contains(a.first ?? "") {
            state.openCLI(a); output += "→ opened `boat \(args)` in Terminal (interactive)\n"; return
        }
        output += "\n$ boat \(args)\n"
        running = true
        task = Task {
            defer { running = false; stopper = nil }
            guard let (cli, arguments) = await state.prepareCLI(a), !Task.isCancelled else { return }
            let (stream, stop) = BoatCLI.stream(cli, arguments)
            stopper = stop
            for await chunk in stream { output = String((output + stripANSI(chunk)).suffix(250_000)) }
            await state.refreshSandboxes(silent: true)
        }
    }
}
