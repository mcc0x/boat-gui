import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.section) {
                Section("Manage") {
                    ForEach(NavSection.allCases) { s in
                        Label {
                            HStack {
                                Text(s.rawValue)
                                Spacer()
                                if s == .sandboxes, !state.sandboxes.isEmpty {
                                    Text("\(state.runningCount)/\(state.sandboxes.count)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: { Image(systemName: s.icon) }
                        .tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { AccountFooter() }
        } detail: {
            Group {
                if !state.hasKey && state.section != .cli {
                    OnboardingView()
                } else {
                    switch state.section ?? .sandboxes {
                    case .sandboxes: SandboxesView()
                    case .environments: EnvironmentsView()
                    case .snapshots: SnapshotsView()
                    case .webhooks: WebhooksView()
                    case .apiKeys: APIKeysView()
                    case .account: AccountView()
                    case .cli: CLIConsoleView()
                    }
                }
            }
            .overlay(alignment: .topTrailing) { ToastOverlay() }
        }
        .task { await state.refreshAll() }
        .sheet(isPresented: $state.showNewSandbox) { NewSandboxSheet() }
    }
}

struct AccountFooter: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Image(systemName: "person.circle.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.me?["user"]?.first("login", "name", "email")?.string
                         ?? state.me?.first("login", "email")?.string ?? (state.hasKey ? "Connected" : "Not signed in"))
                        .font(.caption.weight(.semibold)).lineLimit(1)
                    if let h = state.limits?.first("creditBalanceHours")?.double {
                        Text(String(format: "%.1f h credit", h)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if state.loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @VState private var key = ""
    @VState private var working = false
    @VState private var msg: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sailboat.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Welcome to Boat Deck").font(.largeTitle.bold())
            Text("Manage your boat.dev sandboxes, agents, environments and snapshots from your Mac.")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste an API key").font(.headline)
                    HStack {
                        SecureField("boat_…", text: $key).textFieldStyle(.roundedBorder)
                        Button("Connect") { state.apiKey = key; Task { await state.refreshAll() } }
                            .keyboardShortcut(.defaultAction).disabled(key.isEmpty)
                    }
                    Divider()
                    Text("…or let the boat CLI create one").font(.headline)
                    Text(state.cliPath.map { "Found CLI at \($0)" } ?? "boat CLI not found — install it first.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Install CLI in Terminal") {
                            BoatCLI.openInTerminal("/bin/zsh", ["-lc", "curl -fsSL https://boat.dev/install | sh"])
                        }
                        Button("boat login in Terminal") {
                            if let p = state.cliPath { BoatCLI.openInTerminal(p, ["login"]) }
                        }.disabled(state.cliPath == nil)
                        Button {
                            Task { await createKeyViaCLI() }
                        } label: {
                            if working { ProgressView().controlSize(.small) } else { Text("Create key with CLI") }
                        }
                        .disabled(state.cliPath == nil || working)
                        Button("Re-detect") { state.relocateCLI() }
                    }
                    if let msg { Text(msg).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                .padding(8)
            }
            .frame(maxWidth: 560)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func createKeyViaCLI() async {
        guard let p = state.cliPath else { return }
        working = true; defer { working = false }
        let name = "boat-deck-\(Host.current().localizedName?.replacingOccurrences(of: " ", with: "-") ?? "mac")"
        let r = await BoatCLI.run(p, ["api-key", "create", name, "--preset", "admin", "--json"])
        let j = r.json
        let secret = j?.first("key", "secret", "token", "apiKey")?.string
            ?? j?["apiKey"]?.first("key", "secret", "token")?.string
            ?? j?["key"]?.first("secret", "key", "token")?.string
            ?? r.stdout.split(whereSeparator: { $0.isWhitespace || $0 == "\"" })
                .map(String.init).first(where: { $0.hasPrefix("boat_") || $0.hasPrefix("bk_") || $0.hasPrefix("sk_") })
        if let secret, r.exitCode == 0 {
            state.apiKey = secret
            await state.refreshAll()
        } else {
            msg = "Couldn't read a key from the CLI (exit \(r.exitCode)). Output:\n\(r.stdout)\(r.stderr)\nTip: run `boat login` first, then retry — or paste a key above."
        }
    }
}
