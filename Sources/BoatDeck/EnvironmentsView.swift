import SwiftUI

struct EnvironmentsView: View {
    @EnvironmentObject var state: AppState
    @VState private var selected: String?
    @VState private var error: String?

    var body: some View {
        HSplitView {
            List(state.environments, selection: $selected) { e in
                HStack {
                    Image(systemName: "leaf.fill").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(e.displayName).font(.body.weight(.medium))
                        Text("v\(e["version"] ?? "?") · \(e.json["vars"]?.array?.count ?? 0) vars · \(e.json["repos"]?.array?.count ?? 0) repos")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if e.json["isDefault"]?.bool == true { Text("default").font(.caption2).padding(3).background(.tint.opacity(0.2), in: Capsule()) }
                }
                .tag(e.id)
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            .overlay { if state.environments.isEmpty { EmptyStateView(icon: "leaf", title: "No environments", message: error ?? "") } }

            Group {
                if let s = selected, let env = state.environments.first(where: { $0.id == s }) {
                    EnvironmentDetail(env: env, reload: reload).id(env.id + (env["version"] ?? ""))
                } else {
                    EmptyStateView(icon: "leaf", title: "Select an environment",
                                   message: "Environments bundle repos, env vars, secret files and credentials that sandboxes boot with.")
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Environments")
        .toolbar {
            Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button {
                guard let n = promptText("New environment", "Name", ok: "Create") else { return }
                Task { await state.runOrCLI("Environment created", cli: ["env", "new", n]) { try await $0.createEnvironment(name: n) }; await reload() }
            } label: { Label("New Environment", systemImage: "plus") }
        }
        .task { await reload() }
    }

    func reload() async {
        do { state.environments = try await state.api.environments(); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct EnvironmentDetail: View {
    @EnvironmentObject var state: AppState
    let env: Record
    let reload: () async -> Void
    @VState private var newKey = ""
    @VState private var newValue = ""
    @VState private var repoInput = ""
    @VState private var repoBranch = ""
    @VState private var availableRepos: [Record] = []
    @VState private var reveal = false

    var envId: String { env["id"] ?? env.displayName }
    var name: String { env.displayName }
    var flags: JSON { env.json["flags"] ?? .null }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(name).font(.title2.bold())
                    if env.json["isDefault"]?.bool == true { StateBadge(state: "default") }
                    Spacer()
                    Button("Make default") { Task { await state.cli("Default set", ["env", "default", name]); await reload() } }
                    Button("Rename…") {
                        guard let n = promptText("Rename environment", default: name) else { return }
                        Task { await state.runOrCLI("Renamed", cli: ["env", "rename", name, n]) { try await $0.updateEnvironment(envId, ["name": .string(n)]) }; await reload() }
                    }
                    Button("Upgrade sandboxes") {
                        Task { await state.runOrCLI("Upgrade started", cli: ["env", "upgrade", name]) { try await $0.upgradeEnvironment(envId) } }
                    }
                    Button("Delete…", role: .destructive) {
                        guard confirm("Delete environment \(name)?", "Sandboxes already running are not affected.") else { return }
                        Task { await state.runOrCLI("Environment deleted", cli: ["env", "rm", name]) { try await $0.deleteEnvironment(envId) }; await reload() }
                    }
                }
                GroupBox("Access flags") {
                    VStack(alignment: .leading) {
                        flagToggle("GitHub access", key: "github", cliFlag: "--github")
                        flagToggle("Account secrets", key: "secrets", cliFlag: "--secrets")
                        flagToggle("Safe for third parties", key: "safeForThirdParties", cliFlag: "--safe-for-third-parties", topLevel: true)
                        ForEach((flags.object ?? [:]).keys.sorted().filter { !["github", "secrets"].contains($0) }, id: \.self) { k in
                            HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(flags[k]?.string ?? "—") }
                        }
                    }.padding(6)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(env.json["vars"]?.array ?? [], id: \.self) { v in
                            let k = v.first("key", "name")?.string ?? v.string ?? "?"
                            HStack {
                                Text(k).font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(reveal ? (v["value"]?.string ?? "•••") : "••••••").foregroundStyle(.secondary).textSelection(.enabled)
                                Button { Task { await state.runOrCLI("Removed \(k)", cli: ["env", "rm-var", name, k]) { try await $0.removeVar(envId, key: k) }; await reload() } } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            TextField("KEY", text: $newKey).font(.system(.body, design: .monospaced)).frame(width: 180)
                            SecureField("value", text: $newValue)
                            Button("Set") {
                                let k = newKey, v = newValue
                                Task {
                                    if await state.runOrCLI("Set \(k)", cli: ["env", "set-var", name, "\(k)=\(v)"], { try await $0.setVar(envId, key: k, value: v) }) {
                                        newKey = ""; newValue = ""
                                    }
                                    await reload()
                                }
                            }.disabled(newKey.isEmpty)
                        }
                    }.padding(6)
                } label: {
                    HStack { Text("Variables"); Spacer(); Toggle("Reveal", isOn: $reveal).toggleStyle(.checkbox).controlSize(.small) }
                }
                GroupBox("Secret files") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(env.json.first("secretFiles", "files")?.array ?? [], id: \.self) { f in
                            let p = f.first("path")?.string ?? f.string ?? "?"
                            HStack {
                                Image(systemName: "lock.doc")
                                Text(p).font(.system(.body, design: .monospaced))
                                Spacer()
                                Button { Task { await state.runOrCLI("Removed \(p)", cli: ["env", "rm-file", name, p]) { try await $0.removeSecretFile(envId, path: p) }; await reload() } } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                        }
                        Button("Add secret file from Mac…") { addSecretFile() }
                    }.padding(6)
                }
                GroupBox("Repositories") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(env.json["repos"]?.array ?? [], id: \.self) { r in
                            let n = r.first("name", "fullName", "repo")?.string ?? r.compact
                            let rid = r.first("id", "repositoryId", "databaseId")?.string ?? n
                            HStack {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                Text(n)
                                if let b = r.first("branch", "baseBranch")?.string { Text("@\(b)").foregroundStyle(.secondary) }
                                Spacer()
                                Button { Task { await state.runOrCLI("Removed \(n)", cli: ["env", "rm-repo", name, n]) { try await $0.removeRepo(envId, repoId: rid) }; await reload() } } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            if availableRepos.isEmpty {
                                TextField("owner/repo", text: $repoInput)
                            } else {
                                Picker("Repo", selection: $repoInput) {
                                    Text("Choose…").tag("")
                                    ForEach(availableRepos) { r in
                                        Text(r["fullName", "nameWithOwner", "name"] ?? r.id).tag(r["fullName", "nameWithOwner", "name"] ?? r.id)
                                    }
                                }
                            }
                            TextField("branch (optional)", text: $repoBranch).frame(width: 150)
                            Button("Add") { Task { await addRepo() } }.disabled(repoInput.isEmpty)
                        }
                    }.padding(6)
                }
                GroupBox("All fields") { JSONGrid(json: env.json).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
            }
            .padding()
        }
        .task { availableRepos = (try? await state.api.repos()) ?? [] }
    }

    func flagToggle(_ label: String, key: String, cliFlag: String, topLevel: Bool = false) -> some View {
        let current = (topLevel ? env.json[key] : flags[key])?.bool ?? false
        return Toggle(label, isOn: Binding(get: { current }, set: { v in
            Task {
                var body: [String: JSON] = [:]
                if topLevel { body[key] = .bool(v) } else { body["flags"] = .object([key: .bool(v)]) }
                await state.runOrCLI("\(label) \(v ? "on" : "off")", cli: ["env", "set", name, cliFlag, v ? "true" : "false"]) {
                    try await $0.updateEnvironment(envId, .object(body))
                }
                await reload()
            }
        }))
    }

    func addSecretFile() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let dest = promptText("Path inside the sandbox", default: url.lastPathComponent) else { return }
        Task {
            await state.runOrCLI("Secret file added", cli: ["env", "set-file", name, dest, "--from", url.path]) {
                try await $0.setSecretFile(envId, path: dest, contents: data)
            }
            await reload()
        }
    }

    func addRepo() async {
        let full = repoInput
        let match = availableRepos.first { ($0["fullName", "nameWithOwner", "name"] ?? $0.id) == full }
        let rid = match?["databaseId", "repositoryId", "id"] ?? full
        var cli = ["env", "add-repo", name, full]
        if !repoBranch.isEmpty { cli += ["--branch", repoBranch] }
        let branch = repoBranch
        if await state.runOrCLI("Added \(full)", cli: cli, { try await $0.addRepo(envId, repositoryId: rid, branch: branch) }) {
            repoInput = ""; repoBranch = ""
        }
        await reload()
    }
}
