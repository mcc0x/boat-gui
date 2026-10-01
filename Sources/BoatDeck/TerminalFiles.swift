import SwiftUI
import UniformTypeIdentifiers

func stripANSI(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
}

// MARK: - Terminal

struct TermLine: Identifiable, Equatable {
    let id = UUID()
    enum Kind { case cmd, out, err, meta }
    let kind: Kind
    var text: String
}

struct TerminalView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.detailGutter) var gutter
    let id: String
    @VState private var command = ""
    @AppStorage("term.cwd") private var cwd = ""
    @VState private var timeout = 600
    @VState private var mode = "stream"
    @VState private var lines: [TermLine] = []
    @VState private var running = false
    @VState private var task: Task<Void, Never>?
    @AppStorage("term.history") private var historyRaw = ""
    @VState private var histIndex: Int? = nil
    @VState private var detachedPid = ""
    @VFocusState private var focused: Bool

    var history: [String] { historyRaw.isEmpty ? [] : historyRaw.components(separatedBy: "\u{1F}") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 10, height: 10)
                }
                Text("\(id) — exec").font(.bdMonoSmall).foregroundStyle(BD.text3).padding(.leading, 6)
                Spacer()
                PillPicker(options: [PillOption(value: "stream", label: "Stream"), PillOption(value: "sync", label: "Wait"),
                                     PillOption(value: "detached", label: "Detached")], selection: $mode)
                    .scaleEffect(0.9)
                Menu {
                    Button("Clear screen") { lines.removeAll() }
                    Button("Copy output") { copyToClipboard(lines.map(\.text).joined(separator: "\n")) }
                    Divider()
                    Menu("Timeout") {
                        ForEach([60, 300, 600, 1800, 3600, 7200], id: \.self) { t in
                            Button((timeout == t ? "✓ " : "") + durationText(Double(t))) { timeout = t }
                        }
                    }
                    Divider()
                    Button("Clear history") { historyRaw = "" }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(BD.text2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text("Run any command inside the sandbox. ↑/↓ for history.\n")
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                        ForEach(lines) { l in
                            Group {
                                switch l.kind {
                                case .cmd:
                                    (Text("❯ ").foregroundColor(BD.green) + Text(l.text).foregroundColor(.white).bold())
                                        .padding(.top, 8)
                                case .out: Text(l.text.hasSuffix("\n") ? String(l.text.dropLast()) : l.text).foregroundColor(Color.white.opacity(0.88))
                                case .err: Text(l.text.hasSuffix("\n") ? String(l.text.dropLast()) : l.text).foregroundColor(BD.red.opacity(0.9))
                                case .meta: Text(l.text).foregroundColor(Color.white.opacity(0.4))
                                }
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if running {
                            HStack(spacing: 6) { Spinner(size: 10, color: .white.opacity(0.5)); Text("running…").foregroundColor(.white.opacity(0.4)) }
                                .padding(.top, 4)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(14)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: lines) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 8) {
                TextField("~", text: $cwd)
                    .textFieldStyle(.plain).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    .frame(width: 130)
                    .help("Working directory")
                Text("❯").font(.system(size: 13, design: .monospaced)).foregroundColor(BD.green)
                TextField("", text: $command, prompt: Text("command").foregroundColor(.white.opacity(0.25)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($focused)
                    .onSubmit { runIt() }
                    .onKeyPress(.upArrow) { recall(-1); return .handled }
                    .onKeyPress(.downArrow) { recall(1); return .handled }
                if running {
                    Button("Stop") { task?.cancel(); addLine(TermLine(kind: .meta, text: "^C (stopped watching)")) }
                        .bdButton(.danger, .small)
                } else {
                    Button { runIt() } label: {
                        Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                            .foregroundColor(command.isEmpty ? .white.opacity(0.3) : .black)
                            .frame(width: 26, height: 22)
                            .background(command.isEmpty ? Color.white.opacity(0.08) : BD.green, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain).help("Run (↩)").disabled(command.isEmpty)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if !detachedPid.isEmpty {
                HStack {
                    Text("detached \(detachedPid)").font(.bdMonoSmall).foregroundColor(.white.opacity(0.5))
                    Button("Status") {
                        Task {
                            if let r = try? await state.api.commandStatus(id, pid: detachedPid) {
                                addLine(TermLine(kind: .meta, text: r.pretty))
                            }
                        }
                    }.bdButton(.ghost, .small)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.035), in: RoundedRectangle(cornerRadius: BD.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BD.r3, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, gutter).padding(.top, 20).padding(.bottom, 24)
        .onAppear { focused = true }
        .onDisappear { task?.cancel() }
    }

    func recall(_ dir: Int) {
        let h = history
        guard !h.isEmpty else { return }
        var i = histIndex ?? h.count
        i = max(0, min(h.count, i + dir))
        histIndex = i
        command = i < h.count ? h[i] : ""
    }

    func pushHistory(_ c: String) {
        var h = history.filter { $0 != c }
        h.append(c)
        historyRaw = h.suffix(100).joined(separator: "\u{1F}")
        histIndex = nil
    }

    func addLine(_ line: TermLine) {
        var bounded = line
        bounded.text = String(line.text.suffix(20_000))
        lines.append(bounded)
        trimOutput()
    }

    func trimOutput() {
        var characters = lines.reduce(0) { $0 + $1.text.count }
        while lines.count > 1000 || characters > 250_000 {
            characters -= lines.removeFirst().text.count
        }
    }

    func out(_ s: String, err: Bool = false) {
        let clean = stripANSI(s)
        guard !clean.isEmpty else { return }
        let kind: TermLine.Kind = err ? .err : .out
        // Stored text keeps its newlines; a chunk continues the previous line only if that line is unterminated.
        if let last = lines.last, last.kind == kind, !last.text.hasSuffix("\n"), last.text.count < 20000 {
            lines[lines.count - 1].text = String((lines[lines.count - 1].text + clean).suffix(20_000))
            trimOutput()
        } else {
            addLine(TermLine(kind: kind, text: clean))
        }
    }

    func runIt() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty, !running else { return }
        if cmd == "clear" { lines.removeAll(); command = ""; return }
        pushHistory(cmd)
        command = ""
        addLine(TermLine(kind: .cmd, text: cmd))
        running = true
        task = Task {
            defer { running = false }
            do {
                switch mode {
                case "detached":
                    let r = try await state.api.execDetached(id, command: cmd, cwd: cwd)
                    detachedPid = r.first("processId", "pid")?.string ?? ""
                    addLine(TermLine(kind: .meta, text: "started detached process \(detachedPid)"))
                case "sync":
                    append(try await state.api.exec(id, command: cmd, cwd: cwd, timeout: timeout))
                default:
                    // A failed stream may already have executed the command. Never replay it.
                    for try await ev in state.api.execStream(id, command: cmd, cwd: cwd, timeout: timeout) {
                        switch ev["type"]?.string ?? "" {
                        case "stdout": out(ev.first("data", "text")?.string ?? "")
                        case "stderr": out(ev.first("data", "text")?.string ?? "", err: true)
                        case "exit": exitLine(ev.first("exitCode", "code")?.int)
                        case "started": break
                        default:
                            if ev["stdout"] != nil || ev["exitCode"] != nil { append(ev) } else { addLine(TermLine(kind: .meta, text: ev.compact)) }
                        }
                    }
                }
            } catch is CancellationError {
                // Stop watching never starts another command.
            } catch {
                guard !Task.isCancelled else { return }
                addLine(TermLine(kind: .err, text: "error: \(error.localizedDescription)"))
            }
        }
    }

    func exitLine(_ code: Int?) {
        addLine(TermLine(kind: .meta, text: code == 0 ? "✓ exit 0" : "✗ exit \(code.map(String.init) ?? "?")"))
    }

    func append(_ r: JSON) {
        if let o = r.first("stdout", "output")?.string { out(o) }
        if let e = r["stderr"]?.string, !e.isEmpty { out(e, err: true) }
        if let c = r.first("exitCode", "exit_code")?.int { exitLine(c) }
        if r.first("stdout", "output", "exitCode") == nil { addLine(TermLine(kind: .meta, text: r.pretty)) }
    }
}

// MARK: - Files

struct FileEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDir: Bool
    let isLink: Bool
    let size: Double
    let mtime: Double

    var icon: String {
        if isDir { return "folder.fill" }
        if isLink { return "link" }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "js", "ts", "tsx", "jsx", "py", "go", "rs", "rb", "java", "c", "h", "cpp", "sh", "zsh": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist", "env", "ini", "conf": return "curlybraces"
        case "md", "txt", "rtf", "log": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
        case "zip", "tar", "gz", "tgz", "xz", "7z": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "lock": return "lock"
        default: return name.hasPrefix(".") ? "eye.slash" : "doc"
        }
    }
}

struct FilesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.detailGutter) var gutter
    @Environment(\.contentWidth) var width
    let id: String
    @AppStorage("files.path") private var path = "/home/user"
    @AppStorage("files.hidden") private var showHidden = true
    @VState private var entries: [FileEntry] = []
    @VState private var selection: String?
    @VState private var error: String?
    @VState private var loading = false
    @VState private var openFile: String?
    @VState private var fileText = ""
    @VState private var fileOriginal = ""
    @VState private var fileBinary: Data?
    @VState private var dropTarget = false
    @VState private var filter = ""

    var shown: [FileEntry] {
        entries.filter { (showHidden || !$0.name.hasPrefix(".")) && (filter.isEmpty || $0.name.lowercased().contains(filter.lowercased())) }
    }

    /// Narrow windows show one pane at a time: the editor replaces the list while a file is open.
    var stacked: Bool { width < 820 }

    var body: some View {
        HStack(spacing: 0) {
            if !stacked || openFile == nil {
            VStack(spacing: 0) {
                toolbar
                Hairline()
                if let error { Text(error).font(.bdSmall).foregroundStyle(BD.red).padding(10).textSelection(.enabled) }
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if loading && entries.isEmpty { ForEach(0..<6, id: \.self) { _ in SkeletonRow() } }
                        ForEach(shown) { e in
                            FileRow(e: e, selected: selection == e.name)
                                .onTapGesture(count: 2) { activate(e.name) }
                                .onTapGesture { selection = e.name }
                                .contextMenu {
                                    Button("Open") { activate(e.name) }
                                    Button("Download…") { Task { await download(e.name) } }
                                    Button("Copy path") { copyToClipboard(join(e.name)) }
                                    Button("Rename…") { rename(e.name) }
                                    Divider()
                                    Button("Delete…", role: .destructive) { delete(e.name) }
                                }
                        }
                    }
                    .padding(6)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if dropTarget {
                        RoundedRectangle(cornerRadius: BD.r2).strokeBorder(BD.text, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .background(BD.surface)
                            .overlay(Label("Drop to upload to \(path)", systemImage: "arrow.down.doc").foregroundStyle(BD.text))
                            .padding(8)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in await uploadURL(url) } }
                        }
                    }
                    return true
                }
                Hairline()
                HStack {
                    Text("\(shown.count) items").font(.bdSmall).foregroundStyle(BD.text3)
                    Spacer()
                    Toggle("Hidden files", isOn: $showHidden).toggleStyle(.checkbox).font(.bdSmall)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .frame(maxWidth: stacked ? .infinity : 400)
            .padding(.leading, gutter - 10)
            }
            if !stacked || openFile != nil {
                if !stacked { Rectangle().fill(BD.stroke).frame(width: 1) }
                editor.padding(.horizontal, stacked ? gutter - 10 : 0)
            }
        }
        .padding(.bottom, 8)
        .animation(BD.snappy, value: openFile)
        .task { await list() }
    }

    var crumbs: [(String, String)] {
        var out: [(String, String)] = [("/", "/")]
        var acc = ""
        for part in path.split(separator: "/") { acc += "/" + part; out.append((String(part), acc)) }
        return out
    }

    var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                IconButton(icon: "chevron.up", help: "Parent folder", size: 24) { go((path as NSString).deletingLastPathComponent) }
                    .disabled(path == "/")
                IconButton(icon: "house", help: "Home", size: 24) { go("~home") }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(crumbs, id: \.1) { c in
                            Button(c.0) { go(c.1) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: c.1 == path ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(c.1 == path ? BD.text : BD.text2)
                            if c.1 != path && c.1 != "/" { Text("/").font(.bdMonoSmall).foregroundStyle(BD.text3) }
                        }
                    }
                }
                Spacer(minLength: 0)
                IconButton(icon: "arrow.clockwise", help: "Refresh", size: 24) { Task { await list() } }
            }
            HStack(spacing: 6) {
                SearchField(text: $filter, prompt: "Filter")
                IconButton(icon: "square.and.arrow.up", help: "Upload files…", size: 28) { upload() }
                IconButton(icon: "folder.badge.plus", help: "New folder", size: 28) { newFolder() }
            }
        }
        .padding(10)
    }

    @ViewBuilder var editor: some View {
        if let f = openFile {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: FileEntry(name: (f as NSString).lastPathComponent, isDir: false, isLink: false, size: 0, mtime: 0).icon)
                        .foregroundStyle(BD.text2)
                    Text((f as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundStyle(BD.text)
                    if fileText != fileOriginal { Circle().fill(BD.amber).frame(width: 6, height: 6).transition(.scale) }
                    Text(f).font(.bdMonoSmall).foregroundStyle(BD.text3).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if fileBinary == nil {
                        Button("Revert") { fileText = fileOriginal }.bdButton(.ghost, .small).disabled(fileText == fileOriginal)
                        Button { Task { await save() } } label: { Label("Save", systemImage: "square.and.arrow.down") }
                            .bdButton(.primary, .small).keyboardShortcut("s").disabled(fileText == fileOriginal)
                    }
                    IconButton(icon: "xmark", size: 24) { withAnimation(BD.snappy) { openFile = nil } }
                }
                .padding(12)
                .animation(BD.snappy, value: fileText == fileOriginal)
                Hairline()
                if let bin = fileBinary {
                    VStack(spacing: 14) {
                        if let img = NSImage(data: bin) {
                            Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)).padding(20)
                        } else {
                            EmptyStateView(icon: "doc.zipper", title: "Binary file", message: byteString(Double(bin.count)))
                        }
                        Button("Save to Mac…") { saveData(bin, name: (f as NSString).lastPathComponent) }.bdButton().padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CodeEditor(text: $fileText)
                }
            }
            .transition(.opacity)
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "No file open",
                           message: "Double-click a file to view or edit it. Drag files from Finder onto the list to upload.")
        }
    }

    // MARK: actions

    func join(_ n: String) -> String { path == "/" ? "/" + n : path + "/" + n }

    func go(_ p: String) {
        if p == "~home" {
            Task {
                if let r = try? await state.api.exec(id, command: "echo $HOME", cwd: nil),
                   let h = r["stdout"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty { path = h }
                await list()
            }
            return
        }
        path = p.isEmpty ? "/" : p
        selection = nil
        Task { await list() }
    }

    func list() async {
        loading = true; defer { loading = false }
        let cmd = "cd \(shq(path)) && find . -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%T@\\t%f\\n' 2>/dev/null | head -n 5000"
        do {
            let r = try await state.api.exec(id, command: cmd, cwd: nil, timeout: 60)
            if let code = r.first("exitCode")?.int, code != 0 {
                error = "Can't open \(path) " + (r["stderr"]?.string ?? "") + " (exit \(code))"
                entries = []
                return
            }
            let out = r.first("stdout", "output")?.string ?? ""
            let parsed: [FileEntry] = out.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 4 else { return nil }
                return FileEntry(name: String(parts[3]), isDir: parts[0] == "d", isLink: parts[0] == "l",
                                 size: Double(parts[1]) ?? 0, mtime: Double(parts[2]) ?? 0)
            }
            withAnimation(BD.snappy) {
                entries = parsed.sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func activate(_ name: String) {
        guard let e = entries.first(where: { $0.name == name }) else { return }
        if e.isDir || (e.isLink && !name.contains(".")) { go(join(name)) } else { Task { await open(join(name)) } }
    }

    func open(_ p: String) async {
        do {
            if let entry = entries.first(where: { join($0.name) == p }), entry.size > Double(LocalFiles.previewLimit) {
                state.toast("File too large to preview. Use Download to save it to your Mac.", error: true)
                return
            }
            let (data, _) = try await state.api.readFile(id, path: p)
            try Task.checkCancellation()
            withAnimation(BD.snappy) {
                openFile = p
                if let s = String(data: data, encoding: .utf8), data.count < 5_000_000, !data.contains(0) {
                    fileBinary = nil; fileText = s; fileOriginal = s
                } else {
                    fileBinary = data
                }
            }
        } catch { state.toast("Open failed — \(error.localizedDescription)", error: true) }
    }

    func save() async {
        guard let f = openFile else { return }
        do {
            let savedText = fileText
            try await state.api.writeFile(id, path: f, data: Data(savedText.utf8))
            if openFile == f { fileOriginal = savedText }
            state.toast("Saved \((f as NSString).lastPathComponent)")
        } catch { state.toast("Save failed — \(error.localizedDescription)", error: true) }
    }

    func upload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { for u in panel.urls { await uploadURL(u) } }
    }

    func uploadURL(_ u: URL) async {
        let client = state.api
        do {
            let d = try await LocalFiles.read(u, limit: LocalFiles.uploadLimit)
            guard state.api === client, !Task.isCancelled else { return }
            try await client.writeFile(id, path: join(u.lastPathComponent), data: d)
            state.toast("Uploaded \(u.lastPathComponent)")
            await list()
        } catch { state.toast("Upload failed — \(error.localizedDescription)", error: true) }
    }

    func download(_ n: String) async {
        do {
            let (file, resp) = try await state.api.downloadFile(id, path: join(n))
            defer { try? FileManager.default.removeItem(at: file) }
            let isDir = (resp.value(forHTTPHeaderField: "X-Snapshot-Entry-Kind") ?? "") == "dir"
            let panel = NSSavePanel()
            panel.nameFieldStringValue = isDir ? n + ".tar" : n
            if panel.runModal() == .OK, let destination = panel.url {
                try await LocalFiles.saveDownload(file, to: destination)
                state.toast("Saved \(destination.lastPathComponent)")
            }
        } catch { state.toast("Download failed — \(error.localizedDescription)", error: true) }
    }

    func saveData(_ d: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            do { try d.write(to: url); state.toast("Saved \(url.lastPathComponent)") } catch { state.toast(error.localizedDescription, error: true) }
        }
    }

    func newFolder() {
        guard let n = promptText("New folder", default: "untitled") else { return }
        Task { await sh("mkdir -p \(shq(join(n)))", "Folder created") }
    }
    func rename(_ n: String) {
        guard let new = promptText("Rename", default: n), new != n else { return }
        Task { await sh("mv \(shq(join(n))) \(shq(join(new)))", "Renamed") }
    }
    func delete(_ n: String) {
        guard confirm("Delete \(n)?", join(n)) else { return }
        Task { await sh("rm -rf \(shq(join(n)))", "Deleted") }
    }
    func sh(_ cmd: String, _ ok: String) async {
        await state.run(ok, refresh: false) {
            let result = try await $0.exec(id, command: cmd, cwd: nil)
            guard result.first("exitCode", "exit_code")?.int == 0 else {
                throw BoatError(status: 0, code: "command_failed", message: result["stderr"]?.string ?? "File operation failed.")
            }
            return result
        }
        await list()
    }
}

struct FileRow: View {
    let e: FileEntry
    let selected: Bool
    @VState private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: e.icon).font(.system(size: 12)).foregroundStyle(e.isDir ? BD.text : BD.text2).frame(width: 18)
            Text(e.name).font(.system(size: 12.5)).foregroundStyle(BD.text).lineLimit(1)
            Spacer()
            Text(e.isDir ? "" : byteString(e.size)).font(.system(size: 11).monospacedDigit()).foregroundStyle(BD.text3)
            Text(Date(timeIntervalSince1970: e.mtime), format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(size: 11)).foregroundStyle(BD.text3).frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? BD.surfaceHi : hover ? BD.surface : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Monospaced editor with a line-number gutter.
struct CodeEditor: View {
    @Binding var text: String
    var body: some View {
        let count = max(1, text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } })
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                Text((1...min(count, 20000)).map(String.init).joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(BD.text3)
                    .multilineTextAlignment(.trailing)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(BD.surface)
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: CGFloat(count) * 15 + 40)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
