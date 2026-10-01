import SwiftUI

struct EnvironmentsView: View {
    @EnvironmentObject var state: AppState
    @VState private var selected: String?
    @VState private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Environments").font(.bdTitle).foregroundStyle(BD.text)
                    Spacer()
                    IconButton(icon: "plus", help: "New environment") { create() }
                }
                Text("Repos, variables, secret files and credentials sandboxes boot with.")
                    .font(.bdBody).foregroundStyle(BD.text2)
                ScrollView {
                    VStack(spacing: 6) {
                        if state.environments.isEmpty {
                            if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red) }
                            else { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                        }
                        ForEach(Array(state.environments.enumerated()), id: \.element.id) { i, e in
                            EnvRow(env: e, selected: selected == e.id)
                                .tapAction { withAnimation(BD.spring) { selected = e.id } }
                                .appear(delay: 0.03 * Double(i))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 20)
            .frame(width: 264)
            Rectangle().fill(BD.stroke).frame(width: 1)

            Group {
                if let s = selected, let env = state.environments.first(where: { $0.id == s }) {
                    EnvironmentDetail(env: env, reload: reload)
                        .id(env.id)
                        .transition(.opacity.combined(with: .offset(x: 12)))
                } else {
                    EmptyStateView(icon: "leaf", title: "Select an environment",
                                   message: "Each sandbox boots with an environment: GitHub repos cloned, variables exported, secret files written.",
                                   actionTitle: state.environments.isEmpty ? "Create environment" : nil) { create() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(BD.spring, value: selected)
        .task {
            await reload()
            if selected == nil { selected = state.environments.first(where: { $0.json["isDefault"]?.bool == true })?.id ?? state.environments.first?.id }
        }
    }

    func create() {
        guard let n = promptText("New environment", "Name", ok: "Create") else { return }
        Task { await state.runOrCLI("Environment created", cli: ["env", "new", n]) { try await $0.createEnvironment(name: n) }; await reload() }
    }

    func reload() async {
        do { let e = try await state.api.environments(); withAnimation(BD.spring) { state.environments = e }; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct EnvRow: View {
    let env: Record
    let selected: Bool
    @VState private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill").font(.system(size: 13)).foregroundStyle(BD.text)
                .frame(width: 32, height: 32).background(BD.surfaceHi, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(env.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(BD.text)
                    if env.json["isDefault"]?.bool == true { Chip(text: "default") }
                }
                Text("v\(env.envVersion) · \(env.envVars.count) vars · \(env.envRepos.count) repos")
                    .font(.bdSmall).foregroundStyle(BD.text3)
            }
            Spacer()
        }
        .padding(10)
        .background(selected ? BD.surfaceHi : hover ? BD.surface : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? BD.stroke : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
        Page {
            PageHeader(title: name, subtitle: "Version \(env.envVersion)\(env.json["isDefault"]?.bool == true ? " · default environment" : "")") {
                HStack(spacing: 8) {
                    if env.json["isDefault"]?.bool != true {
                        Button("Make default") { Task { await state.cli("Default set", ["env", "default", name]); await reload() } }.bdButton()
                    }
                    Button { Task { await state.runOrCLI("Upgrade started", cli: ["env", "upgrade", name]) { try await $0.upgradeEnvironment(envId) } } } label: {
                        Label("Upgrade sandboxes", systemImage: "arrow.up.circle")
                    }.bdButton()
                    Menu {
                        Button("Rename…") {
                            guard let n = promptText("Rename environment", default: name) else { return }
                            Task { await state.runOrCLI("Renamed", cli: ["env", "rename", name, n]) { try await $0.updateEnvironment(envId, ["name": .string(n)]) }; await reload() }
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            guard confirm("Delete environment \(name)?", "Sandboxes already running are not affected.") else { return }
                            Task { await state.runOrCLI("Environment deleted", cli: ["env", "rm", name]) { try await $0.deleteEnvironment(envId) }; await reload() }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .background(BD.surface, in: Circle()).overlay(Circle().strokeBorder(BD.stroke, lineWidth: 1))
                }
            }
            .appear()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { accessSection; reposSection }.frame(minWidth: 820)
                VStack(spacing: 14) { accessSection; reposSection }
            }
            .appear(delay: 0.05)

            section("Variables", "dollarsign.square", trailing: AnyView(
                Toggle("Reveal values", isOn: $reveal.animation(BD.soft)).toggleStyle(.switch).controlSize(.mini).font(.bdSmall)
            )) {
                VStack(spacing: 0) {
                    if env.envVars.isEmpty { Text("No variables yet.").font(.bdSmall).foregroundStyle(BD.text3).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6) }
                    ForEach(env.envVars, id: \.0) { (k, val) in
                        HStack {
                            Text(k).font(.bdMono).foregroundStyle(BD.text)
                            Spacer()
                            Text(reveal ? val : "••••••••").font(.bdMonoSmall).foregroundStyle(BD.text2)
                                .textSelection(.enabled).lineLimit(1).frame(maxWidth: 360, alignment: .trailing)
                            IconButton(icon: "trash", size: 24) {
                                Task { await state.runOrCLI("Removed \(k)", cli: ["env", "rm-var", name, k]) { try await $0.removeVar(envId, key: k) }; await reload() }
                            }
                        }
                        .padding(.vertical, 6)
                        Hairline()
                    }
                    HStack {
                        Field(placeholder: "KEY", text: $newKey, mono: true).frame(width: 220)
                        Field(placeholder: "value", text: $newValue, secure: true)
                        Button { Task { await setVar() } } label: { Label("Set", systemImage: "plus") }
                            .bdButton(.primary, .small).disabled(newKey.isEmpty)
                    }
                    .padding(.top, 10)
                }
            }
            .appear(delay: 0.1)

            section("Secret files", "lock.doc") {
                VStack(alignment: .leading, spacing: 8) {
                    let files = env.json.first("secretFiles", "files")?.array ?? []
                    if files.isEmpty { Text("No secret files. Add a .env, credentials.json, SSH key…").font(.bdSmall).foregroundStyle(BD.text3) }
                    ForEach(files, id: \.self) { f in
                        let p = f.first("path")?.string ?? f.string ?? "?"
                        HStack {
                            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(BD.text3)
                            Text(p).font(.bdMono).foregroundStyle(BD.text)
                            Spacer()
                            IconButton(icon: "trash", size: 24) {
                                Task { await state.runOrCLI("Removed \(p)", cli: ["env", "rm-file", name, p]) { try await $0.removeSecretFile(envId, path: p) }; await reload() }
                            }
                        }
                    }
                    Button { addSecretFile() } label: { Label("Add secret file from Mac…", systemImage: "plus") }.bdButton(.secondary, .small)
                }
            }
            .appear(delay: 0.14)

            DisclosureGroup {
                JSONGrid(json: env.json).padding(.top, 8)
            } label: { Eyebrow(text: "All fields") }
            .glassCard()
        }
        .task { availableRepos = (try? await state.api.repos()) ?? [] }
    }

    var accessSection: some View {
                section("Access", "lock.shield") {
                    VStack(spacing: 10) {
                        flagToggle("GitHub access", "Pass your GitHub login so private repos clone", key: "passGithub", cliFlag: "--github", topLevel: true)
                        Hairline()
                        flagToggle("Account secrets", "Expose your saved secrets", key: "passSecrets", cliFlag: "--secrets", topLevel: true)
                        Hairline()
                        flagToggle("Sandbox credentials", "Pass boat credentials into the sandbox", key: "passSandboxCredentials", cliFlag: "", topLevel: true)
                        Hairline()
                        flagToggle("Agent credentials", "Pass Claude Code / Codex logins to agents", key: "passAgentsCredentials", cliFlag: "", topLevel: true)
                        Hairline()
                        flagToggle("Safe for third parties", "Allow sharing with collaborators", key: "safeForThirdParties", cliFlag: "--safe-for-third-parties", topLevel: true)
                    }
                }
    }

    var reposSection: some View {
                section("Repositories", "chevron.left.forwardslash.chevron.right") {
                    VStack(alignment: .leading, spacing: 8) {
                        let repos = env.envRepos
                        if repos.isEmpty { Text("No repositories yet.").font(.bdSmall).foregroundStyle(BD.text3) }
                        ForEach(repos, id: \.self) { r in
                            let n = r.first("name", "fullName", "repo")?.string ?? r.compact
                            let rid = r.first("id", "repositoryId", "databaseId")?.string ?? n
                            HStack {
                                Image(systemName: "arrow.triangle.branch").foregroundStyle(BD.text3)
                                Text(n).font(.system(size: 12.5, weight: .medium)).foregroundStyle(BD.text)
                                if let b = r.first("branch", "baseBranch")?.string { Chip(text: b, mono: true) }
                                Spacer()
                                IconButton(icon: "trash", size: 24) {
                                    Task { await state.runOrCLI("Removed \(n)", cli: ["env", "rm-repo", name, n]) { try await $0.removeRepo(envId, repoId: rid) }; await reload() }
                                }
                            }
                        }
                        HStack {
                            if availableRepos.isEmpty {
                                Field(placeholder: "owner/repo", text: $repoInput, mono: true)
                            } else {
                                Picker("", selection: $repoInput) {
                                    Text("Choose a repository…").tag("")
                                    ForEach(availableRepos) { r in
                                        let n = r["fullName", "nameWithOwner", "name"] ?? r.id
                                        Text(n).tag(n)
                                    }
                                }
                                .labelsHidden()
                            }
                            Field(placeholder: "branch", text: $repoBranch, mono: true).frame(width: 100)
                            Button("Add") { Task { await addRepo() } }.bdButton(.primary, .small).disabled(repoInput.isEmpty)
                        }
                    }
                }
    }

    func section<C: View>(_ title: String, _ icon: String, trailing: AnyView? = nil, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(BD.text2)
                Text(title).font(.bdH3).foregroundStyle(BD.text)
                Spacer()
                if let trailing { trailing }
            }
            c()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    func flagToggle(_ label: String, _ sub: String, key: String, cliFlag: String, topLevel: Bool = false) -> some View {
        let current = (topLevel ? env.json[key] : flags[key])?.bool ?? false
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(BD.text)
                Text(sub).font(.bdSmall).foregroundStyle(BD.text3)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { current }, set: { v in
                Task {
                    var body: [String: JSON] = [:]
                    if topLevel { body[key] = .bool(v) } else { body["flags"] = .object([key: .bool(v)]) }
                    let msg = "\(label) \(v ? "on" : "off")"
                    if cliFlag.isEmpty {
                        await state.run(msg, refresh: false) { try await $0.updateEnvironment(envId, .object(body)) }
                    } else {
                        await state.runOrCLI(msg, cli: ["env", "set", name, cliFlag, v ? "true" : "false"]) {
                            try await $0.updateEnvironment(envId, .object(body))
                        }
                    }
                    await reload()
                }
            }))
            .toggleStyle(.switch).labelsHidden()
        }
    }

    func setVar() async {
        let k = newKey, v = newValue
        if await state.runOrCLI("Set \(k)", cli: ["env", "set-var", name, "\(k)=\(v)"], { try await $0.setVar(envId, key: k, value: v) }) {
            newKey = ""; newValue = ""
        }
        await reload()
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

extension Record {
    /// Variables: either a `vars` array or KEY=VALUE lines in `envContents`.
    var envVars: [(String, String)] {
        if let a = json["vars"]?.array {
            return a.map { ($0.first("key", "name")?.string ?? "?", $0["value"]?.string ?? "") }
        }
        let text = json["envContents"]?.string ?? ""
        return text.split(separator: "\n").compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { return nil }
            var v = String(l[l.index(after: eq)...])
            if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
            return (String(l[..<eq]).replacingOccurrences(of: "export ", with: ""), v)
        }
    }
    var envRepos: [JSON] { json.first("selectedRepositories", "repos")?.array ?? [] }
    var envVersion: String { self["latestVersionNumber", "version"] ?? "1" }
}
