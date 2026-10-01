import SwiftUI

struct AgentEvent: Identifiable {
    let id = UUID()
    var kind: String
    var convo: String?
    var text: String
    var raw: JSON
}

struct AgentTab: View {
    @EnvironmentObject var state: AppState
    let id: String

    @VState private var convos: [Record] = []
    @VState private var listSel: String? = "__all__"
    var selectedConvo: String? { listSel == "__all__" ? nil : listSel }
    @VState private var events: [AgentEvent] = []
    @VState private var streaming = false
    @VState private var streamTask: Task<Void, Never>?
    @VState private var prompt = ""
    @VState private var newConvo = false
    @VState private var catalog: [String: [String]] = [:]
    @VState private var efforts: [String: [String]] = [:]
    @AppStorage("agent.provider") private var provider = ""
    @AppStorage("agent.model") private var model = ""
    @AppStorage("agent.effort") private var effort = ""
    @VState private var sending = false
    @VState private var showRaw = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Conversations").font(.headline)
                    Spacer()
                    Button { Task { await loadConvos() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                }
                .padding(10)
                List(selection: $listSel) {
                    Label("All activity", systemImage: "tray.full").tag("__all__")
                    ForEach(convos) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if c.json["running"]?.bool == true {
                                    ProgressView().controlSize(.mini)
                                }
                                Text(c["lastPromptPreview", "title"] ?? c.id).lineLimit(2)
                            }
                            Text([c["lastHarness", "provider"], c["lastModel", "model"], relative(c["lastActivity"])]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(c.id)
                        .contextMenu { Button("Copy conversation ID") { copyToClipboard(c.id) } }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            VStack(spacing: 0) {
                HStack {
                    Circle().fill(streaming ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(streaming ? "Live" : "Disconnected").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Raw", isOn: $showRaw).toggleStyle(.switch).controlSize(.mini)
                    Button("Clear") { events.removeAll() }.controlSize(.small)
                    Button { Task { await state.run("Interrupted", refresh: false) { try await $0.interrupt(id, convo: selectedConvo) } } } label: {
                        Label("Interrupt", systemImage: "stop.circle")
                    }
                    .controlSize(.small).tint(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(visibleEvents) { e in EventRow(e: e, raw: showRaw) }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(12)
                    }
                    .onChange(of: events.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                .overlay {
                    if events.isEmpty {
                        EmptyStateView(icon: "sparkles", title: "No agent activity yet",
                                       message: "Send a prompt below — Claude Code, Codex or another coding agent runs inside the sandbox.")
                    }
                }
                Divider()
                composer
            }
        }
        .task {
            await loadConvos()
            await loadCatalog()
            connect()
        }
        .onChange(of: listSel) { _ in events.removeAll(); connect() }
        .onDisappear { streamTask?.cancel() }
    }

    var visibleEvents: [AgentEvent] {
        guard let c = selectedConvo else { return events }
        return events.filter { $0.convo == nil || $0.convo == c }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Agent", selection: $provider) {
                    Text("Default").tag("")
                    ForEach(catalog.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    if !provider.isEmpty && catalog[provider] == nil { Text(provider).tag(provider) }
                }
                .frame(maxWidth: 200)
                Picker("Model", selection: $model) {
                    Text("Default").tag("")
                    ForEach(catalog[provider] ?? [], id: \.self) { Text($0).tag($0) }
                    if !model.isEmpty && !(catalog[provider] ?? []).contains(model) { Text(model).tag(model) }
                }
                .frame(maxWidth: 240)
                Picker("Effort", selection: $effort) {
                    Text("Default").tag("")
                    ForEach(efforts["\(provider)/\(model)"] ?? ["none", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 160)
                Toggle("New conversation", isOn: $newConvo).toggleStyle(.checkbox)
            }
            .controlSize(.small)
            HStack(alignment: .bottom) {
                TextField(selectedConvo == nil || newConvo ? "Ask the agent to do something…" : "Continue this conversation…",
                          text: $prompt, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }
                Button { Task { await steer() } } label: { Text("Steer") }
                    .help("Send a message into the running turn")
                    .disabled(prompt.isEmpty)
                Button { Task { await send() } } label: {
                    if sending { ProgressView().controlSize(.small) } else { Label("Send", systemImage: "paperplane.fill") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(prompt.isEmpty || sending)
            }
        }
        .padding(10)
    }

    func connect() {
        streamTask?.cancel()
        let convo = selectedConvo
        streamTask = Task {
            while !Task.isCancelled {
                streaming = true
                do {
                    for try await ev in state.api.events(id, convo: convo, follow: true) {
                        ingest(ev)
                    }
                } catch {
                    if !Task.isCancelled {
                        events.append(AgentEvent(kind: "error", convo: nil, text: "Stream: \(error.localizedDescription)", raw: .null))
                    }
                }
                streaming = false
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func ingest(_ ev: JSON) {
        let type = ev["type"]?.string ?? "event"
        let convo = ev.first("conversationId", "conversation")?.string
        let data = ev["data"] ?? .null
        var text: String
        switch type {
        case let t where t.hasSuffix(".text") || t.hasSuffix("message"):
            text = data.first("text", "content", "message")?.string ?? ev.first("text", "message")?.string ?? ""
            // Merge streaming text into the previous chunk.
            if let last = events.last, last.kind == type, last.convo == convo {
                if text.hasPrefix(last.text) { events[events.count - 1].text = text }
                else { events[events.count - 1].text += text }
                events[events.count - 1].raw = ev
                return
            }
        case let t where t.contains("tool_call"):
            let tools = data["tools"]?.array ?? [data]
            text = tools.map { t in
                let n = t.first("name", "tool")?.string ?? "tool"
                let a = t.first("args", "input", "arguments").map { $0.string ?? $0.compact } ?? ""
                return "▸ \(n) \(a)"
            }.joined(separator: "\n")
        case let t where t.contains("tool_result"):
            text = data.first("result", "output", "content").map { $0.string ?? $0.compact } ?? data.compact
            if text.count > 4000 { text = String(text.prefix(4000)) + "\n… (truncated)" }
        default:
            text = data == .null ? ev.compact : (data.first("text", "message", "state")?.string ?? data.compact)
        }
        events.append(AgentEvent(kind: type, convo: convo, text: text, raw: ev))
        if events.count > 3000 { events.removeFirst(500) }
        if type.contains("done") || type.contains("complete") || type.contains("finished") {
            Task { await loadConvos() }
        }
    }

    func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true; defer { sending = false }
        var b: [String: JSON] = ["prompt": .string(text)]
        if !provider.isEmpty { b["provider"] = .string(provider) }
        if !model.isEmpty { b["model"] = .string(model) }
        if !effort.isEmpty { b["reasoningEffort"] = .string(effort) }
        if newConvo { b["new"] = true } else if let c = selectedConvo { b["conversationId"] = .string(c) }
        events.append(AgentEvent(kind: "you", convo: selectedConvo, text: text, raw: .object(b)))
        if let r = await state.run("Prompt queued", refresh: false, { try await $0.prompt(id, .object(b)) }) {
            prompt = ""
            newConvo = false
            await loadConvos()
            if let c = r["conversationId"]?.string, selectedConvo != c, selectedConvo != nil { listSel = c }
        }
    }

    func steer() async {
        let text = prompt
        if await state.run("Steered", refresh: false, { try await $0.steer(id, message: text, convo: selectedConvo) }) != nil {
            events.append(AgentEvent(kind: "you (steer)", convo: selectedConvo, text: text, raw: .null))
            prompt = ""
        }
    }

    func loadConvos() async {
        if let c = try? await state.api.conversations(id) {
            convos = c.sorted { ($0["lastActivity"] ?? "") > ($1["lastActivity"] ?? "") }
        }
    }

    func loadCatalog() async {
        guard let j = try? await state.api.providerModels() else { return }
        var cat: [String: [String]] = [:]
        var eff: [String: [String]] = [:]
        func models(_ v: JSON) -> [JSON] { v["models"]?.array ?? v.array ?? [] }
        func addProvider(_ name: String, _ v: JSON) {
            var names: [String] = []
            for m in models(v) {
                let mid = m.string ?? m.first("id", "model", "name")?.string ?? ""
                if mid.isEmpty { continue }
                names.append(mid)
                if let e = m.first("reasoningEfforts", "reasoningEffort", "efforts")?.array {
                    eff["\(name)/\(mid)"] = e.compactMap { $0.string }
                }
            }
            cat[name] = names
        }
        if let arr = j.first("providers")?.array {
            for p in arr { addProvider(p.first("id", "provider", "name")?.string ?? "?", p) }
        } else if let o = (j.first("providers") ?? j).object {
            for (k, v) in o where !["ok", "type"].contains(k) { addProvider(k, v) }
        }
        catalog = cat
        efforts = eff
    }
}

struct EventRow: View {
    let e: AgentEvent
    let raw: Bool
    var color: Color {
        if e.kind.hasPrefix("you") { return .accentColor }
        if e.kind.contains("tool_call") { return .purple }
        if e.kind.contains("tool_result") { return .teal }
        if e.kind.contains("error") { return .red }
        if e.kind.hasPrefix("sandbox") { return .orange }
        return .primary
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.kind).font(.caption2.weight(.semibold)).foregroundStyle(color.opacity(0.8))
            if raw {
                Text(e.raw.pretty).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            } else {
                Text(e.text)
                    .font(e.kind.contains("tool") ? .system(size: 12, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(color.opacity(e.kind.hasPrefix("you") ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
