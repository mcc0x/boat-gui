import SwiftUI

struct SandboxesView: View {
    @EnvironmentObject var state: AppState
    @VState private var filter = "all"
    @VState private var search = ""

    var filtered: [Record] {
        state.sandboxes.filter { s in
            let f: Bool
            switch filter {
            case "active": f = !["archived", "stopped", "error"].contains(s.state)
            case "archived": f = ["archived", "stopped"].contains(s.state)
            case "error": f = s.state == "error"
            default: f = true
            }
            let q = search.lowercased()
            return f && (q.isEmpty || s.id.lowercased().contains(q) || s.displayName.lowercased().contains(q)
                         || (s["environment"] ?? "").lowercased().contains(q))
        }
        .sorted { ($0["createdAt"] ?? "") > ($1["createdAt"] ?? "") }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    Text("All").tag("all")
                    Text("Active").tag("active")
                    Text("Archived").tag("archived")
                    Text("Error").tag("error")
                }
                .pickerStyle(.segmented).labelsHidden().padding(8)
                List(filtered, selection: $state.selectedSandbox) { s in
                    SandboxRow(s: s).tag(s.id)
                        .contextMenu { SandboxQuickActions(id: s.id) }
                }
                .overlay {
                    if state.sandboxes.isEmpty {
                        EmptyStateView(icon: "shippingbox", title: "No sandboxes",
                                       message: state.lastError ?? "Create one with ⇧⌘N")
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            Group {
                if let id = state.selectedSandbox {
                    SandboxDetailView(sandboxId: id).id(id)
                } else {
                    EmptyStateView(icon: "sailboat", title: "Select a sandbox",
                                   message: "Each sandbox is an isolated Linux VM with Docker, Node, Python, Go, Rust and coding agents.")
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter sandboxes")
        .navigationTitle("Sandboxes")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await state.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { state.showNewSandbox = true } label: { Label("New Sandbox", systemImage: "plus") }
            }
        }
    }
}

struct SandboxRow: View {
    let s: Record
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(s.stateColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.displayName).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(s.state)
                    if let t = s["machineType", "type", "size"] { Text("· \(t)") }
                    if let e = s["environment", "environmentName"] { Text("· \(e)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(relative(s["createdAt", "created_at"])).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

/// Lifecycle actions shared by context menus and the menu bar.
struct SandboxQuickActions: View {
    @EnvironmentObject var state: AppState
    let id: String
    var body: some View {
        Button("Copy ID") { copyToClipboard(id) }
        Button("SSH in Terminal") { if let p = state.cliPath { BoatCLI.openInTerminal(p, ["ssh", id]) } }
            .disabled(state.cliPath == nil)
        Button("Open Desktop") {
            Task {
                if let r = await state.run("Desktop ready", refresh: false, { try await $0.desktop(id) }),
                   let u = r["url"]?.string, let url = URL(string: u) { NSWorkspace.shared.open(url) }
            }
        }
        Divider()
        Button("Stop (snapshot)") { Task { await state.run("Stopping \(id)") { try await $0.stop(id) } } }
        Button("Resume") { Task { await state.run("Resuming \(id)") { try await $0.resume(id) } } }
        Button("Fork") { Task { await state.run("Forked \(id)") { try await $0.fork(id) } } }
        Button("Extend 1 hour") {
            Task { await state.run("Extended \(id)") { api in
                let cur = try await api.sandbox(id)["ttlSeconds"]?.double ?? 3600
                return try await api.updateSandbox(id, ["ttlSeconds": .number(cur + 3600)])
            } }
        }
        Divider()
        Button("Delete…", role: .destructive) {
            if confirm("Delete \(id)?", "This permanently deletes the sandbox and its snapshots.") {
                Task { await state.run("Deleting \(id)") { try await $0.delete(id) } }
                if state.selectedSandbox == id { state.selectedSandbox = nil }
            }
        }
    }
}

struct NewSandboxSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @VState private var name = ""
    @VState private var type = "default"
    @VState private var ttlHours = 1.0
    @VState private var noAutoStop = false
    @VState private var environment = ""
    @VState private var noEnv = false
    @VState private var noSnapshots = false
    @VState private var from = ""
    @VState private var envVars: [EnvPair] = []
    @VState private var setupScript = ""
    @VState private var firstPrompt = ""
    @VState private var creating = false

    struct EnvPair: Identifiable { let id = UUID(); var key = ""; var value = "" }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Sandbox").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form {
                TextField("Name (optional)", text: $name)
                Picker("Machine size", selection: $type) {
                    Text("Small").tag("small")
                    Text("Default · 4 vCPU / 8 GB").tag("default")
                    Text("Large").tag("large")
                }
                Toggle("Keep running (no auto-stop)", isOn: $noAutoStop)
                if !noAutoStop {
                    Stepper(value: $ttlHours, in: 0.25...72, step: 0.25) {
                        Text("Auto-stop after \(ttlHours, specifier: "%.2g") h")
                    }
                }
                Picker("Environment", selection: $environment) {
                    Text("Default").tag("")
                    ForEach(state.environments) { e in Text(e.displayName).tag(e["name"] ?? e.id) }
                }
                .disabled(noEnv)
                Toggle("Start without environment (--no-env)", isOn: $noEnv)
                Picker("From named snapshot", selection: $from) {
                    Text("Fresh").tag("")
                    ForEach(state.namedSnapshots) { s in Text(s.displayName).tag(s["name"] ?? s.id) }
                }
                Toggle("Disable snapshots", isOn: $noSnapshots)

                SwiftUI.Section("Environment variables") {
                    ForEach($envVars) { $p in
                        HStack {
                            TextField("KEY", text: $p.key).font(.system(.body, design: .monospaced))
                            TextField("value", text: $p.value)
                            Button { envVars.removeAll { $0.id == p.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add variable") { envVars.append(EnvPair()) }
                }
                SwiftUI.Section("Setup script (runs on boot)") {
                    TextEditor(text: $setupScript).font(.system(.body, design: .monospaced)).frame(height: 70)
                }
                SwiftUI.Section("Kick off an agent right away (optional)") {
                    TextField("e.g. Clone my repo and run the tests", text: $firstPrompt, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await create() } } label: {
                    if creating { ProgressView().controlSize(.small) } else { Text("Launch") }
                }
                .keyboardShortcut(.defaultAction).disabled(creating)
            }
            .padding()
        }
        .frame(width: 520, height: 680)
    }

    func create() async {
        creating = true; defer { creating = false }
        var b: [String: JSON] = ["type": .string(type), "noEnv": .bool(noEnv), "noSnapshots": .bool(noSnapshots)]
        if noAutoStop { b["noAutoStop"] = true; b["ttlSeconds"] = 0 } else { b["ttlSeconds"] = .number((ttlHours * 3600).rounded()) }
        if !name.isEmpty { b["name"] = .string(name) }
        if !environment.isEmpty && !noEnv { b["environment"] = .string(environment) }
        if !from.isEmpty { b["from"] = .string(from) }
        let vars = envVars.filter { !$0.key.isEmpty }
        if !vars.isEmpty { b["env"] = .array(vars.map { ["key": .string($0.key), "value": .string($0.value)] }) }
        if !setupScript.isEmpty { b["setupFile"] = .string(Data(setupScript.utf8).base64EncodedString()) }
        guard let r = await state.run("Sandbox launching", { try await $0.createSandbox(.object(b)) }) else { return }
        let sb = r["sandbox"] ?? r
        if let id = sb.first("id", "sandboxId")?.string {
            state.selectedSandbox = id
            if !firstPrompt.isEmpty {
                await state.run("Prompt queued", refresh: false) { try await $0.prompt(id, ["prompt": .string(firstPrompt)]) }
            }
        }
        dismiss()
    }
}
