import SwiftUI

struct AgentEvent: Identifiable, Equatable {
    let id = UUID()
    var sourceID: String? = nil
    var kind: String
    var convo: String?
    var text: String
    var raw: JSON
    var date = Date()

    enum Role { case user, assistant, tool, result, system, error }
    var role: Role {
        if kind == "prompt" || kind.hasPrefix("you") { return .user }
        if kind.contains("tool_call") { return .tool }
        if kind.contains("tool_result") { return .result }
        if kind.contains("error") { return .error }
        if kind == "response" || kind.hasSuffix(".text") || kind.hasSuffix("message") { return .assistant }
        return .system
    }
}

struct AgentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UIPrefs
    let id: String

    @VState private var convos: [Record] = []
    @VState private var convoSel: String = "__all__"
    @VState private var events: [AgentEvent] = []
    @VState private var streaming = false
    @VState private var streamTask: Task<Void, Never>?
    @VState private var prompt = ""
    @VState private var newConvo = false
    @VState private var provider = ""
    @VState private var model = ""
    @VState private var effort = ""
    @VState private var sending = false
    @VState private var showRaw = false
    @VState private var working = false
    @VState private var setup: SetupHint?

    struct SetupHint: Equatable { let message: String; let url: URL }

    var selectedConvo: String? { convoSel == "__all__" ? nil : convoSel }

    @Environment(\.contentWidth) var width
    @Environment(\.detailGutter) var gutter
    var showList: Bool { width >= 880 }

    var body: some View {
        HStack(spacing: 0) {
            if showList {
                conversationList.frame(width: 230)
                    .padding(.leading, gutter - 10).padding(.trailing, 12).padding(.vertical, 14)
                Rectangle().fill(BD.stroke).frame(width: 1)
            }
            VStack(spacing: 0) {
                chatHeader
                Hairline()
                transcript
                if let setup {
                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal").foregroundStyle(BD.amber)
                        Text(setup.message).font(.bdSmall).foregroundStyle(BD.text).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button { NSWorkspace.shared.open(setup.url) } label: { Label("Set up agent", systemImage: "arrow.up.right") }
                            .bdButton(.primary, .small)
                        IconButton(icon: "xmark", size: 22) { withAnimation(BD.snappy) { self.setup = nil } }
                    }
                    .padding(12)
                    .background(BD.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BD.amber.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                composer
            }
            .padding(.horizontal, showList ? 4 : gutter - 14)
        }
        .task {
            provider = state.agentProvider; model = state.agentModel; effort = state.agentEffort
            await loadConvos()
            if state.catalog.isEmpty { await state.loadCatalog() }
            connect()
        }
        .onChange(of: convoSel) { _, _ in events.removeAll(); connect() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: Conversations

    var conversationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Conversations")
                Spacer()
                IconButton(icon: "square.and.pencil", help: "New conversation", size: 24) {
                    withAnimation(BD.spring) { newConvo = true; convoSel = "__all__" }
                }
                IconButton(icon: "arrow.clockwise", help: "Refresh", size: 24) { Task { await loadConvos() } }
            }
            ScrollView {
                VStack(spacing: 4) {
                    convoRow(id: "__all__", title: "All activity", sub: "live event stream", running: streaming, icon: "dot.radiowaves.left.and.right")
                    ForEach(convos) { c in
                        convoRow(id: c.id,
                                 title: c["lastPromptPreview", "title"] ?? "Conversation",
                                 sub: [c["lastHarness", "provider"], c["lastModel", "model"], relative(c["lastActivity"])].compactMap { $0 }.joined(separator: " · "),
                                 running: c.json["running"]?.bool == true, icon: "bubble.left.and.text.bubble.right")
                            .contextMenu { Button("Copy conversation ID") { copyToClipboard(c.id) } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }

    }

    func convoRow(id cid: String, title: String, sub: String, running: Bool, icon: String) -> some View {
        let on = convoSel == cid
        return Button { withAnimation(BD.snappy) { convoSel = cid; newConvo = false } } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(on ? BD.text : BD.text3).frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(BD.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text(sub).font(.system(size: 10.5)).foregroundStyle(BD.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if running { Spinner(size: 10) }
            }
            .padding(8)
            .background(on ? BD.surfaceHi : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Transcript

    var chatHeader: some View {
        HStack(spacing: 10) {
            if !showList {
                Menu {
                    Button("All activity") { convoSel = "__all__" }
                    ForEach(convos) { c in Button(c["lastPromptPreview", "title"] ?? c.id) { convoSel = c.id } }
                    Divider()
                    Button("New conversation") { newConvo = true; convoSel = "__all__" }
                } label: {
                    Label(selectedConvo.flatMap { id in convos.first { $0.id == id }?["lastPromptPreview"] } ?? "All activity", systemImage: "bubble.left.and.text.bubble.right")
                        .labelStyle(TightLabel()).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize().font(.bdSmall)
            }
            HStack(spacing: 6) {
                StatusDot(state: streaming ? "running" : "archived", size: 6)
                Text(streaming ? (working ? "Agent working…" : "Live") : "Connecting…").font(.bdSmall).foregroundStyle(BD.text2)
            }
            if newConvo { Chip(text: "new conversation", icon: "sparkle") }
            Spacer(minLength: 8)
            Menu {
                Toggle("Show raw events", isOn: $showRaw)
                Button("Clear transcript") { withAnimation { events.removeAll() } }
            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(BD.text2) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button { Task { await state.run("Interrupted", refresh: false) { try await $0.interrupt(id, convo: selectedConvo) } } } label: {
                Label("Interrupt", systemImage: "stop.circle")
            }
            .bdButton(.danger, .small)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
    }

    var visibleEvents: [AgentEvent] {
        guard let c = selectedConvo else { return events }
        return events.filter { $0.convo == nil || $0.convo == c }
    }

    var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleEvents) { e in
                        MessageView(e: e, raw: showRaw, expandTools: state.expandTools)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if working { TypingIndicator().transition(.opacity) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
                .animation(BD.spring, value: visibleEvents.count)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: events.count) { _, _ in withAnimation(BD.soft) { proxy.scrollTo("end", anchor: .bottom) } }
            .overlay {
                if visibleEvents.isEmpty {
                    EmptyStateView(icon: "sparkles", title: "Put an agent to work",
                                   message: "Claude Code, Codex or another coding agent runs inside this sandbox. Describe a task below — it can clone, build, test and commit.")
                }
            }
        }
    }

    // MARK: Composer

    var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                menuChip(icon: "cpu", title: provider.isEmpty ? "Agent: default" : provider) {
                    Button("Default") { provider = ""; model = "" }
                    ForEach(state.catalog.keys.sorted(), id: \.self) { p in Button(p) { provider = p; model = "" } }
                }
                menuChip(icon: "brain", title: model.isEmpty ? "Model: default" : model) {
                    Button("Default") { model = "" }
                    ForEach(state.catalog[provider] ?? state.catalog.values.flatMap { $0 }, id: \.self) { m in Button(m) { model = m } }
                }
                menuChip(icon: "dial.medium", title: effort.isEmpty ? "Effort: default" : "Effort: \(effort)") {
                    Button("Default") { effort = "" }
                    ForEach(state.efforts["\(provider)/\(model)"] ?? ["none", "low", "medium", "high", "xhigh", "max"], id: \.self) { e in
                        Button(e) { effort = e }
                    }
                }
                Toggle("New conversation", isOn: $newConvo.animation(BD.snappy)).toggleStyle(.checkbox).font(.bdSmall).fixedSize()
                    .padding(.leading, 4).frame(height: 24)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(selectedConvo == nil || newConvo ? "Ask the agent to do something…" : "Continue this conversation…",
                          text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...8)
                    .padding(.vertical, 8)
                    .onSubmit { Task { await send() } }
                Button { Task { await steer() } } label: { Label("Steer", systemImage: "arrow.turn.down.right") }
                    .bdButton(.ghost, .small)
                    .help("Send into the running turn without starting a new one")
                    .disabled(prompt.isEmpty)
                Button { Task { await send() } } label: {
                    ZStack {
                        Circle().fill(prompt.isEmpty ? BD.surfaceHi : prefs.accent.color)
                        if sending { Spinner(size: 12, color: prefs.accent.onColor) }
                        else { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(prompt.isEmpty ? BD.text3 : prefs.accent.onColor) }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(prompt.isEmpty || sending)
                .animation(BD.soft, value: prompt.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(BD.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BD.strokeHi, lineWidth: 1))
            Text("⌘↩ send · Steer nudges a running turn · Interrupt stops it").font(.system(size: 10.5)).foregroundStyle(BD.text3)
        }
        .padding(14)
    }

    func menuChip<C: View>(icon: String, title: String, @ViewBuilder _ items: () -> C) -> some View {
        Menu { items() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(BD.text2)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(BD.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BD.stroke, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Streaming

    /// boat.dev serves events as a paginated list, so we poll it and append anything new.
    func connect() {
        streamTask?.cancel()
        let convo = selectedConvo
        let client = state.api
        streamTask = Task {
            var pager = EventPager()
            while !Task.isCancelled {
                do {
                    let response = try await client.call("GET", client.sb(id) + "/events",
                        query: ["conversation": convo, "limit": "100", "sort": "asc", "cursor": pager.cursor])
                    try Task.checkCancellation()
                    let page = try pager.accept(response)
                    for event in page.events { ingest(event) }
                    streaming = true
                    if page.hasMore { continue } // Drain every page before waiting.
                } catch {
                    guard !Task.isCancelled else { return }
                    streaming = false
                    if let error = error as? BoatError, [401, 403].contains(error.status) {
                        events.append(AgentEvent(kind: "error", convo: nil, text: "This API key can't read agent events (\(error.message)).", raw: .null))
                        return
                    }
                }
                do { try await Task.sleep(nanoseconds: working ? 1_500_000_000 : 4_000_000_000) }
                catch { return }
            }
        }
    }

    func ingest(_ ev: JSON) {
        let type = ev["type"]?.string ?? "event"
        let convo = ev.first("conversationId", "conversation")?.string
        let data = ev["data"] ?? .null
        var text: String
        if type == "response" || type.hasSuffix(".text") || type.hasSuffix("message") {
            working = data["is_streaming"]?.bool ?? false
            text = data.first("text", "content", "message")?.string ?? ev.first("text", "message")?.string ?? ""
        } else if type.contains("tool_call") {
            working = true
            let tools = data["tools"]?.array ?? [data]
            text = tools.map { t in
                let n = t.first("name", "tool")?.string ?? "tool"
                let a = t.first("args", "input", "arguments").map { $0.string ?? $0.compact } ?? ""
                return "\(n)\t\(a)"
            }.joined(separator: "\n")
        } else if type.contains("tool_result") {
            text = data.first("result", "output", "content").map { $0.string ?? $0.compact } ?? data.compact
            if text.count > 6000 { text = String(text.prefix(6000)) + "\n… (truncated)" }
        } else {
            text = data == .null ? ev.compact : (data.first("text", "message", "state")?.string ?? data.compact)
        }
        let sourceID = ev.first("id", "eventId", "seq")?.string ?? ev.compact
        if let index = events.firstIndex(where: { $0.sourceID == sourceID }) {
            events[index].text = text; events[index].raw = ev
        } else {
            events.append(AgentEvent(sourceID: sourceID, kind: type, convo: convo, text: text, raw: ev))
        }
        if events.count > 3000 { events.removeFirst(500) }
        if type.contains("done") || type.contains("complete") || type.contains("finished") || type.contains("idle") {
            working = false
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
        withAnimation(BD.spring) { events.append(AgentEvent(kind: "you", convo: selectedConvo, text: text, raw: .object(b))) }
        prompt = ""
        do {
            let r = try await state.api.prompt(id, .object(b))
            withAnimation(BD.snappy) { setup = nil }
            state.toast("Prompt queued")
            working = true
            newConvo = false
            await loadConvos()
            if let c = r["conversationId"]?.string, selectedConvo != nil, selectedConvo != c { convoSel = c }
        } catch let e as BoatError {
            if let url = e.setupURL {
                withAnimation(BD.spring) { setup = SetupHint(message: e.message, url: url) }
            } else {
                state.toast("Prompt failed — \(e.localizedDescription)", error: true)
            }
            prompt = text
        } catch {
            state.toast("Prompt failed — \(error.localizedDescription)", error: true)
            prompt = text
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
            withAnimation(BD.spring) { convos = c.sorted { ($0["lastActivity"] ?? "") > ($1["lastActivity"] ?? "") } }
        }
    }
}

struct MessageView: View {
    let e: AgentEvent
    let raw: Bool
    let expandTools: Bool
    @VState private var expanded: Bool? = nil

    var isExpanded: Bool { expanded ?? expandTools }

    var body: some View {
        if raw {
            Text(e.raw.pretty).font(.bdMonoSmall).foregroundStyle(BD.text2).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).panel()
        } else {
            switch e.role {
            case .user:
                HStack {
                    Spacer(minLength: 80)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(e.text).font(.system(size: 13.5)).foregroundStyle(BD.inverse).textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(BD.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if e.kind.contains("steer") { Text("steer").font(.system(size: 10)).foregroundStyle(BD.text3) }
                    }
                }
            case .assistant:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(BD.text)
                        .frame(width: 24, height: 24).background(BD.surfaceHi, in: Circle())
                    Text(markdown(e.text)).font(.system(size: 13.5)).foregroundStyle(BD.text).textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)
                }
            case .tool, .result:
                VStack(alignment: .leading, spacing: 6) {
                    Button { withAnimation(BD.snappy) { expanded = !isExpanded } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: e.role == .tool ? "wrench.and.screwdriver" : "arrow.turn.down.left")
                                .font(.system(size: 10.5)).foregroundStyle(e.role == .tool ? BD.violet : BD.teal)
                            Text(summary).font(.bdMonoSmall).foregroundStyle(BD.text2).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(BD.text3)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isExpanded {
                        Text(e.text.replacingOccurrences(of: "\t", with: "  ")).font(.bdMonoSmall).foregroundStyle(BD.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity)
                    }
                }
                .padding(.leading, 34)
                .panel(radius: 10, padding: 9)
            case .error:
                Label(e.text, systemImage: "exclamationmark.triangle").font(.bdSmall).foregroundStyle(BD.red)
            case .system:
                HStack(spacing: 8) {
                    Rectangle().fill(BD.stroke).frame(height: 1)
                    Text("\(e.kind) \(e.text.count < 60 ? e.text : "")").font(.system(size: 10.5)).foregroundStyle(BD.text3).lineLimit(1).fixedSize()
                    Rectangle().fill(BD.stroke).frame(height: 1)
                }
            }
        }
    }

    var summary: String {
        let first = e.text.split(separator: "\n").first.map(String.init) ?? ""
        return (e.role == .tool ? "" : "result  ") + first.replacingOccurrences(of: "\t", with: "  ")
    }

    func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(BD.text)
                .frame(width: 24, height: 24).background(BD.surfaceHi, in: Circle())
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate * 5
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(BD.text2).frame(width: 6, height: 6)
                            .opacity(0.3 + 0.7 * max(0, sin(t - Double(i) * 0.9)))
                            .offset(y: -2 * max(0, sin(t - Double(i) * 0.9)))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(BD.surface, in: Capsule())
        }
    }
}
