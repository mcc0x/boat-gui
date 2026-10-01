import SwiftUI
import UniformTypeIdentifiers

struct TerminalTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @VState private var command = ""
    @AppStorage("term.cwd") private var cwd = ""
    @VState private var timeout = 600
    @VState private var mode = "stream"
    @VState private var output = ""
    @VState private var running = false
    @VState private var task: Task<Void, Never>?
    @VState private var history: [String] = []
    @VState private var detachedPid = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Working dir (optional)", text: $cwd).frame(width: 220).font(.system(.body, design: .monospaced))
                Picker("", selection: $mode) {
                    Text("Stream").tag("stream")
                    Text("Wait").tag("sync")
                    Text("Detached").tag("detached")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                Stepper("Timeout \(timeout)s", value: $timeout, in: 10...86400, step: 60).fixedSize()
                Spacer()
                Menu("History") {
                    ForEach(history.reversed(), id: \.self) { h in Button(h) { command = h } }
                }
                .frame(width: 90).disabled(history.isEmpty)
                Button("Clear") { output = "" }
            }
            .controlSize(.small)
            .padding(8)
            LogView(text: output)
            Divider()
            HStack {
                Text("$").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                TextField("command… (e.g. docker ps, git status, npm test)", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { runIt() }
                if running {
                    Button("Stop") { task?.cancel(); running = false; output += "\n^C (stopped watching)\n" }
                } else {
                    Button("Run") { runIt() }.keyboardShortcut(.defaultAction).disabled(command.isEmpty)
                }
            }
            .padding(10)
            if !detachedPid.isEmpty {
                HStack {
                    Text("Detached process \(detachedPid)").font(.caption.monospaced())
                    Button("Check status") {
                        Task {
                            if let r = try? await state.api.commandStatus(id, pid: detachedPid) {
                                output += "\n[status \(detachedPid)]\n\(r.pretty)\n"
                            }
                        }
                    }.controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
    }

    func runIt() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        history.removeAll { $0 == cmd }; history.append(cmd)
        command = ""
        output += "\n$ \(cmd)\n"
        running = true
        task = Task {
            defer { running = false }
            do {
                switch mode {
                case "detached":
                    let r = try await state.api.execDetached(id, command: cmd, cwd: cwd)
                    detachedPid = r.first("processId", "pid")?.string ?? ""
                    output += "started detached \(detachedPid)\n"
                case "sync":
                    let r = try await state.api.exec(id, command: cmd, cwd: cwd, timeout: timeout)
                    append(r)
                default:
                    var got = false
                    do {
                        for try await ev in state.api.execStream(id, command: cmd, cwd: cwd, timeout: timeout) {
                            got = true
                            let t = ev["type"]?.string ?? ""
                            switch t {
                            case "stdout", "stderr": output += ev.first("data", "text")?.string ?? ""
                            case "exit": output += "\n[exit \(ev.first("exitCode", "code")?.string ?? "?")]\n"
                            case "started": break
                            default:
                                if ev["stdout"] != nil || ev["exitCode"] != nil { append(ev) } else { output += ev.compact + "\n" }
                            }
                        }
                    } catch let streamErr where !got {
                        _ = streamErr
                        let r = try await state.api.exec(id, command: cmd, cwd: cwd, timeout: timeout)
                        append(r)
                    }
                }
            } catch {
                output += "error: \(error.localizedDescription)\n"
            }
        }
    }

    func append(_ r: JSON) {
        if let o = r.first("stdout", "output")?.string { output += o }
        if let e = r["stderr"]?.string, !e.isEmpty { output += e }
        if let c = r.first("exitCode", "exit_code")?.string { output += "\n[exit \(c)]\n" }
        if r.first("stdout", "output", "exitCode") == nil { output += r.pretty + "\n" }
    }
}

struct FileEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDir: Bool
    let isLink: Bool
    let size: Double
    let mtime: Double
}

struct FilesTab: View {
    @EnvironmentObject var state: AppState
    let id: String
    @AppStorage("files.path") private var path = "/home/user"
    @VState private var pathField = ""
    @VState private var entries: [FileEntry] = []
    @VState private var selection: Set<String> = []
    @VState private var error: String?
    @VState private var loading = false
    @VState private var openFile: String?
    @VState private var fileText = ""
    @VState private var fileOriginal = ""
    @VState private var fileBinary: Data?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { go((path as NSString).deletingLastPathComponent) } label: { Image(systemName: "arrow.up") }
                    .disabled(path == "/")
                Button { go("~home") } label: { Image(systemName: "house") }
                TextField("Path", text: $pathField).font(.system(.body, design: .monospaced)).onSubmit { go(pathField) }
                Button { Task { await list() } } label: { Image(systemName: "arrow.clockwise") }
                Divider().frame(height: 16)
                Button { upload() } label: { Label("Upload", systemImage: "square.and.arrow.up") }
                Button { newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Button { Task { await downloadSelection() } } label: { Label("Download", systemImage: "square.and.arrow.down") }
                    .disabled(selection.isEmpty)
            }
            .controlSize(.small).padding(8)
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal).textSelection(.enabled) }
            HSplitView {
                Table(entries, selection: $selection) {
                    TableColumn("Name") { e in
                        Label(e.name, systemImage: e.isDir ? "folder.fill" : (e.isLink ? "link" : "doc"))
                            .foregroundStyle(e.isDir ? Color.accentColor : .primary)
                    }
                    TableColumn("Size") { e in Text(e.isDir ? "—" : byteString(e.size)).foregroundStyle(.secondary) }.width(80)
                    TableColumn("Modified") { e in
                        Text(Date(timeIntervalSince1970: e.mtime), style: .relative).foregroundStyle(.secondary)
                    }.width(110)
                }
                .contextMenu(forSelectionType: String.self) { names in
                    Button("Open") { if let n = names.first { activate(n) } }
                    Button("Download") { selection = names; Task { await downloadSelection() } }
                    Button("Copy path") { if let n = names.first { copyToClipboard(join(n)) } }
                    Button("Rename…") { if let n = names.first { rename(n) } }
                    Divider()
                    Button("Delete…", role: .destructive) { delete(names) }
                } primaryAction: { names in
                    if let n = names.first { activate(n) }
                }
                .overlay { if loading { ProgressView() } }
                .frame(minWidth: 300)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in await uploadURL(url) } }
                        }
                    }
                    return true
                }

                editor.frame(minWidth: 300)
            }
        }
        .task { await list() }
    }

    @ViewBuilder var editor: some View {
        if let f = openFile {
            VStack(spacing: 0) {
                HStack {
                    Text(f).font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if fileBinary == nil {
                        Button("Revert") { fileText = fileOriginal }.disabled(fileText == fileOriginal)
                        Button("Save") { Task { await save() } }.keyboardShortcut("s").disabled(fileText == fileOriginal)
                    }
                    Button { openFile = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .controlSize(.small).padding(8)
                if let bin = fileBinary {
                    VStack(spacing: 10) {
                        if let img = NSImage(data: bin) {
                            Image(nsImage: img).resizable().scaledToFit().padding()
                        } else {
                            EmptyStateView(icon: "doc.zipper", title: "Binary file", message: byteString(Double(bin.count)))
                        }
                        Button("Save to Mac…") { saveData(bin, name: (f as NSString).lastPathComponent) }
                    }
                } else {
                    TextEditor(text: $fileText)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        } else {
            EmptyStateView(icon: "doc.text", title: "No file open", message: "Double-click a file to view or edit it. Drop files here to upload.")
        }
    }

    func join(_ n: String) -> String { path == "/" ? "/" + n : path + "/" + n }

    func go(_ p: String) {
        if p == "~home" {
            Task {
                if let r = try? await state.api.exec(id, command: "echo $HOME", cwd: nil),
                   let h = r["stdout"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
                    path = h
                }
                await list()
            }
            return
        }
        path = p.isEmpty ? "/" : p
        Task { await list() }
    }

    func list() async {
        loading = true; defer { loading = false }
        pathField = path
        let cmd = "cd \(shq(path)) && find . -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%T@\\t%f\\n' 2>/dev/null | head -n 5000"
        do {
            let r = try await state.api.exec(id, command: cmd, cwd: nil, timeout: 60)
            if let code = r.first("exitCode")?.int, code != 0 {
                error = (r["stderr"]?.string ?? "") + " (exit \(code))"
                entries = []
                return
            }
            let out = r.first("stdout", "output")?.string ?? ""
            entries = out.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 4 else { return nil }
                return FileEntry(name: String(parts[3]), isDir: parts[0] == "d", isLink: parts[0] == "l",
                                 size: Double(parts[1]) ?? 0, mtime: Double(parts[2]) ?? 0)
            }
            .sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func activate(_ name: String) {
        guard let e = entries.first(where: { $0.name == name }) else { return }
        if e.isDir || e.isLink && !name.contains(".") {
            go(join(name))
        } else {
            Task { await open(join(name)) }
        }
    }

    func open(_ p: String) async {
        do {
            let (data, _) = try await state.api.readFile(id, path: p)
            openFile = p
            if let s = String(data: data, encoding: .utf8), data.count < 5_000_000, !data.contains(0) {
                fileBinary = nil; fileText = s; fileOriginal = s
            } else {
                fileBinary = data
            }
        } catch {
            state.toast("Open failed — \(error.localizedDescription)", error: true)
        }
    }

    func save() async {
        guard let f = openFile else { return }
        do {
            try await state.api.writeFile(id, path: f, data: Data(fileText.utf8))
            fileOriginal = fileText
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
        guard let d = try? Data(contentsOf: u) else { return }
        do {
            try await state.api.writeFile(id, path: join(u.lastPathComponent), data: d)
            state.toast("Uploaded \(u.lastPathComponent)")
            await list()
        } catch { state.toast("Upload failed — \(error.localizedDescription)", error: true) }
    }

    func downloadSelection() async {
        for n in selection {
            do {
                let (data, resp) = try await state.api.readFile(id, path: join(n))
                let isDir = (resp.value(forHTTPHeaderField: "X-Snapshot-Entry-Kind") ?? "") == "dir"
                saveData(data, name: isDir ? n + ".tar" : n)
            } catch { state.toast("Download failed — \(error.localizedDescription)", error: true) }
        }
    }

    func saveData(_ d: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            do { try d.write(to: url); state.toast("Saved \(url.lastPathComponent)") }
            catch { state.toast(error.localizedDescription, error: true) }
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

    func delete(_ names: Set<String>) {
        guard confirm("Delete \(names.count) item(s)?", names.sorted().joined(separator: "\n")) else { return }
        let args = names.map { shq(join($0)) }.joined(separator: " ")
        Task { await sh("rm -rf \(args)", "Deleted") }
    }

    func sh(_ cmd: String, _ ok: String) async {
        await state.run(ok, refresh: false) { try await $0.exec(id, command: cmd, cwd: nil) }
        await list()
    }
}
