import SwiftUI

struct SandboxesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    @VState private var filter = "all"
    @VState private var search = ""
    @VState private var sort = "newest"

    var filtered: [Record] {
        let q = search.lowercased()
        return state.sandboxes.filter { s in
            let f: Bool
            switch filter {
            case "active": f = s.isActive
            case "archived": f = s.isArchived
            case "error": f = s.state == "error"
            default: f = true
            }
            return f && (q.isEmpty || s.id.lowercased().contains(q) || s.displayName.lowercased().contains(q)
                         || (s["environment"] ?? "").lowercased().contains(q))
        }
        .sorted {
            switch sort {
            case "name": return $0.displayName.lowercased() < $1.displayName.lowercased()
            case "state": return $0.state < $1.state
            default: return ($0["createdAt"] ?? "") > ($1["createdAt"] ?? "")
            }
        }
    }

    func count(_ f: String) -> Int {
        switch f {
        case "active": return state.sandboxes.filter { $0.isActive }.count
        case "archived": return state.sandboxes.filter { $0.isArchived }.count
        case "error": return state.sandboxes.filter { $0.state == "error" }.count
        default: return state.sandboxes.count
        }
    }

    var body: some View {
        WidthReader { w in
            Group {
                if let id = state.selectedSandbox {
                    Group {
                        if w >= 980 {
                            HSplitView {
                                compactList.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                                SandboxDetailView(sandboxId: id)
                                    .frame(minWidth: 450, maxWidth: .infinity)
                                    .layoutPriority(1)
                                    .id(id)
                            }
                        } else {
                            SandboxDetailView(sandboxId: id, showBack: true).id(id)
                        }
                    }
                } else {
                    overview
                }
            }
        }
        .animation(BD.spring, value: state.selectedSandbox)
    }

    // MARK: Overview (grid / list)

    var overview: some View {
        Page {
            PageHeader(title: "Sandboxes", subtitle: "Isolated Linux VMs with Docker, Node, Python, Go, Rust and coding agents.") {
                HStack(spacing: 8) {
                    IconButton(icon: "arrow.clockwise", help: "Refresh (⌘R)") { Task { await state.refreshAll() } }
                    Button { Task { await state.quickLaunch() } } label: { Label("Quick launch", systemImage: "bolt.fill") }.bdButton()
                    Button { state.showNewSandbox = true } label: { Label("New sandbox", systemImage: "plus") }.bdButton(.primary)
                }
            }
            .appear()

            FlowLayout(spacing: 10, lineSpacing: 10) {
                PillPicker(options: [
                    PillOption(value: "all", label: "All \(count("all"))"),
                    PillOption(value: "active", label: "Active \(count("active"))"),
                    PillOption(value: "archived", label: "Archived \(count("archived"))"),
                    PillOption(value: "error", label: "Error \(count("error"))"),
                ], selection: $filter)
                SearchField(text: $search, prompt: "Filter by name, id, environment").frame(width: 250)
                Menu {
                    Picker("Sort", selection: $sort) {
                        Text("Newest first").tag("newest")
                        Text("Name").tag("name")
                        Text("State").tag("state")
                    }
                    .pickerStyle(.inline)
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(height: 30)
                PillPicker(options: [
                    PillOption(value: "list", label: "", icon: "list.bullet"),
                    PillOption(value: "grid", label: "", icon: "square.grid.2x2"),
                ], selection: $prefs.sandboxLayout)
            }
            .appear(delay: 0.04)

            if !state.loadedOnce {
                VStack(spacing: 0) { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
            } else if filtered.isEmpty {
                EmptyStateView(icon: state.sandboxes.isEmpty ? "shippingbox" : "line.3.horizontal.decrease.circle",
                               title: state.sandboxes.isEmpty ? "No sandboxes yet" : "Nothing matches",
                               message: state.lastError ?? (state.sandboxes.isEmpty ? "Launch your first sandbox — it stops itself after an hour unless you say otherwise." : "Try a different filter or search."),
                               actionTitle: state.sandboxes.isEmpty ? "New sandbox" : nil) { state.showNewSandbox = true }
                    .frame(minHeight: 340)
            } else if prefs.sandboxLayout == "grid" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, s in
                        SandboxCard(s: s)
                            .appear(delay: min(0.3, 0.025 * Double(i)))
                            .tapAction { state.open(sandbox: s.id) }
                            .contextMenu { SandboxQuickActions(id: s.id) }
                    }
                }
            } else {
                SandboxTable(rows: filtered)
            }
        }
    }

    // MARK: Compact list (with detail open)

    var compactList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation(BD.spring) { state.selectedSandbox = nil } } label: {
                    Label("All sandboxes", systemImage: "chevron.left")
                }
                .bdButton(.ghost, .small)
                Spacer()
                IconButton(icon: "plus", help: "New sandbox", size: 24) { state.showNewSandbox = true }
            }
            SearchField(text: $search, prompt: "Filter")
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { s in
                        CompactRow(s: s, selected: s.id == state.selectedSandbox)
                            .tapAction { withAnimation(BD.spring) { state.selectedSandbox = s.id } }
                            .contextMenu { SandboxQuickActions(id: s.id) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 12)
        .background(BD.surface.opacity(0.5))
    }
}

struct CompactRow: View {
    let s: Record
    let selected: Bool
    @VState private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: s.state, size: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.displayName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                Text("\(s.state) · \(s.machineType)").font(.system(size: 11.5)).foregroundStyle(BD.text2).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(selected ? BD.surfaceHi : hover ? BD.surface : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(BD.soft, value: hover)
    }
}

/// Grid card. The only surface on the page (no nested panels inside).
struct SandboxCard: View {
    let s: Record
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusDot(state: s.state, size: 7)
                Text(s.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(BD.text).lineLimit(1)
                Spacer(minLength: 6)
                StateBadge(state: s.state)
            }
            Text([s.id, s.specs, s["environment"]].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(BD.text3).lineLimit(1)
            HStack(spacing: 8) {
                if s.isActive, let d = s.archiveAfter, d > Date() {
                    Label("stops " + d.formatted(.relative(presentation: .named, unitsStyle: .narrow)), systemImage: "hourglass")
                } else {
                    Label(relative(s["createdAt", "created_at"]), systemImage: "clock")
                }
                Spacer(minLength: 6)
                if s.isArchived {
                    Button { Task { await state.run("Resuming") { try await $0.resume(s.id) } } } label: { Label("Resume", systemImage: "play.fill") }
                        .bdButton(.secondary, .small)
                } else if s.isActive {
                    Button { Task { await state.run("Stopping") { try await $0.stop(s.id) } } } label: { Label("Stop", systemImage: "stop.fill") }
                        .bdButton(.secondary, .small)
                }
            }
            .labelStyle(TightLabel()).font(.bdSmall).foregroundStyle(BD.text3)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14, padding: 16, interactive: true)
        .hoverLift(1.01)
    }
}

/// Flat table; columns drop out as the page narrows.
struct SandboxTable: View {
    let rows: [Record]
    @EnvironmentObject var state: AppState
    @Environment(\.contentWidth) var width

    var showMachine: Bool { width >= 760 }
    var showEnv: Bool { width >= 900 }
    var showCreated: Bool { width >= 620 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("State").frame(width: 104, alignment: .leading)
                if showMachine { Text("Machine").frame(width: 110, alignment: .leading) }
                if showEnv { Text("Environment").frame(width: 110, alignment: .leading) }
                if showCreated { Text("Created").frame(width: 90, alignment: .trailing) }
            }
            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(BD.text3).textCase(.uppercase)
            .padding(.horizontal, 10).padding(.bottom, 8)
            Hairline()
            ForEach(rows) { s in
                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        StatusDot(state: s.state, size: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(BD.text).lineLimit(1)
                            Text(s.id).font(.bdMonoSmall).foregroundStyle(BD.text3).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StateBadge(state: s.state).frame(width: 104, alignment: .leading)
                    if showMachine { Text(s.specs).font(.bdSmall).foregroundStyle(BD.text2).frame(width: 110, alignment: .leading).lineLimit(1) }
                    if showEnv { Text(s["environment", "environmentName"] ?? "—").font(.bdSmall).foregroundStyle(BD.text2).frame(width: 110, alignment: .leading).lineLimit(1) }
                    if showCreated { Text(relative(s["createdAt"])).font(.bdSmall).foregroundStyle(BD.text3).frame(width: 90, alignment: .trailing).lineLimit(1) }
                }
                .listRow(divider: s.id != rows.last?.id)
                .tapAction { state.open(sandbox: s.id) }
                .contextMenu { SandboxQuickActions(id: s.id) }
            }
        }
    }
}

/// Lifecycle actions shared by context menus, the detail header and the menu bar.
struct SandboxQuickActions: View {
    @EnvironmentObject var state: AppState
    let id: String
    var body: some View {
        Button("Open") { state.open(sandbox: id) }
        Button("Copy ID") { copyToClipboard(id) }
        Button("SSH in Terminal") { state.openCLI(["ssh", id]) }
            .disabled(state.cliPath == nil)
        Button("Open Desktop") {
            Task {
                if let r = await state.run("Desktop ready", refresh: false, { try await $0.desktop(id) }),
                   let u = r["url"]?.string, let url = URL(string: u) { NSWorkspace.shared.open(url) }
            }
        }
        Divider()
        Button("Stop (snapshot)") { Task { await state.run("Stopping") { try await $0.stop(id) } } }
        Button("Resume") { Task { await state.run("Resuming") { try await $0.resume(id) } } }
        Button("Fork") { Task { await state.run("Forked") { try await $0.fork(id) } } }
        Button("Extend 1 hour") {
            Task {
                let left = max(0, state.sandboxes.first { $0.id == id }?.archiveAfter?.timeIntervalSinceNow ?? 0)
                let ttl = Int(left + 3600)
                await state.runAction("Extended by 1h") {
                    try await $0.updateSandbox(id, ["ttlSeconds": .number(Double(ttl))])
                }
                await state.refreshSandboxes(silent: true)
            }
        }
        Button("Save Named Snapshot…") {
            if let n = promptText("Snapshot name", "Named snapshots can seed new sandboxes.") {
                Task { await state.run("Saving snapshot \(n)", refresh: false) { try await $0.saveNamedSnapshot(sandboxId: id, name: n) } }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) {
            if confirm("Delete \(id)?", "This permanently deletes the sandbox and its snapshots.") {
                Task { await state.run("Deleting sandbox") { try await $0.delete(id) } }
                if state.selectedSandbox == id { withAnimation(BD.spring) { state.selectedSandbox = nil } }
            }
        }
    }
}

// MARK: - New sandbox sheet

struct NewSandboxSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
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
    @VState private var showAdvanced = false

    struct EnvPair: Identifiable { let id = UUID(); var key = ""; var value = "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New sandbox").font(.bdH2).foregroundStyle(BD.text)
                    Text("Launches in seconds · snapshots when stopped").font(.bdSmall).foregroundStyle(BD.text2)
                }
                Spacer()
                IconButton(icon: "xmark", help: "Close") { dismiss() }
            }
            .padding(20)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labeled("Name") { Field(placeholder: "my-project (optional)", text: $name) }

                    labeled("Machine") {
                        HStack(spacing: 10) {
                            sizeCard("small", "Small", "Light tasks")
                            sizeCard("default", "Default", "4 vCPU · 8 GB")
                            sizeCard("large", "Large", "Heavy builds")
                        }
                    }

                    labeled("Lifetime") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Keep running — no auto-stop", isOn: $noAutoStop.animation(BD.spring)).toggleStyle(.switch)
                            if !noAutoStop {
                                DurationChips(hours: $ttlHours)
                                    .transition(.opacity)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        labeled("Environment") {
                            Picker("", selection: $environment) {
                                Text("Default").tag("")
                                ForEach(state.environments) { e in Text(e.displayName).tag(e["name"] ?? e.id) }
                            }
                            .labelsHidden().disabled(noEnv)
                        }
                        labeled("Start from") {
                            Picker("", selection: $from) {
                                Text("Fresh machine").tag("")
                                ForEach(state.namedSnapshots) { s in Text(s.displayName).tag(s["name"] ?? s.id) }
                            }
                            .labelsHidden()
                        }
                    }

                    labeled("Kick off an agent (optional)") {
                        TextField("e.g. Clone my repo, install deps and run the tests", text: $firstPrompt, axis: .vertical)
                            .textFieldStyle(.plain).font(.bdBody).lineLimit(2...5)
                            .padding(10)
                            .background(BD.surface, in: RoundedRectangle(cornerRadius: BD.r1, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: BD.r1, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
                    }

                    Button {
                        withAnimation(BD.spring) { showAdvanced.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.right").rotationEffect(.degrees(showAdvanced ? 90 : 0))
                            Text("Advanced")
                            Spacer()
                        }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(BD.text2)
                    }
                    .buttonStyle(.plain)

                    if showAdvanced {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Start without environment (--no-env)", isOn: $noEnv).toggleStyle(.switch)
                            Toggle("Disable snapshots", isOn: $noSnapshots).toggleStyle(.switch)
                            labeled("Environment variables") {
                                VStack(spacing: 6) {
                                    ForEach($envVars) { $p in
                                        HStack {
                                            Field(placeholder: "KEY", text: $p.key, mono: true).frame(width: 180)
                                            Field(placeholder: "value", text: $p.value, secure: true)
                                            IconButton(icon: "minus", size: 24) { envVars.removeAll { $0.id == p.id } }
                                        }
                                    }
                                    Button { withAnimation(BD.spring) { envVars.append(EnvPair()) } } label: {
                                        Label("Add variable", systemImage: "plus")
                                    }
                                    .bdButton(.ghost, .small).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            labeled("Setup script (runs on boot)") {
                                TextEditor(text: $setupScript)
                                    .font(.bdMono).scrollContentBackground(.hidden)
                                    .frame(height: 90).padding(6)
                                    .background(BD.surface, in: RoundedRectangle(cornerRadius: BD.r1, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: BD.r1, style: .continuous).strokeBorder(BD.stroke, lineWidth: 1))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
            }
            Hairline()
            HStack {
                Text("⌘↩ to launch").font(.bdSmall).foregroundStyle(BD.text3)
                Spacer()
                Button("Cancel") { dismiss() }.bdButton(.ghost).keyboardShortcut(.cancelAction)
                Button { Task { await create() } } label: {
                    HStack(spacing: 6) {
                        if creating { Spinner(size: 12, color: prefs.accent.onColor) } else { Image(systemName: "paperplane.fill") }
                        Text(creating ? "Launching…" : "Launch sandbox")
                    }
                }
                .bdButton(.primary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(creating)
            }
            .padding(16)
        }
        .frame(width: 580, height: 680)
        .background(BD.bgRaised)
        .onAppear {
            type = state.defaultType
            ttlHours = state.defaultTTLHours
            environment = state.defaultEnvironment
        }
    }

    func labeled<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { Eyebrow(text: title); c() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func sizeCard(_ value: String, _ title: String, _ sub: String) -> some View {
        let on = type == value
        return Button { withAnimation(BD.snappy) { type = value } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: value == "small" ? "cube" : value == "large" ? "cube.transparent.fill" : "cube.fill")
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? BD.text : BD.text3)
                }
                .font(.system(size: 14))
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.bdSmall).foregroundStyle(BD.text2)
            }
            .foregroundStyle(BD.text)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? BD.surfaceHi : BD.surface, in: RoundedRectangle(cornerRadius: BD.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BD.r2, style: .continuous).strokeBorder(on ? BD.strokeHi : BD.stroke, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
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
            if !firstPrompt.isEmpty {
                let p = firstPrompt
                await state.run("Prompt queued", refresh: false) { try await $0.prompt(id, ["prompt": .string(p)]) }
            }
            if state.openAfterCreate { state.open(sandbox: id) }
        }
        dismiss()
    }
}

func durationText(_ s: Double) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.day, .hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.maximumUnitCount = 2
    return f.string(from: s) ?? "\(Int(s))s"
}
