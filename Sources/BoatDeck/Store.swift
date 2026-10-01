import Foundation
import SwiftUI
import UserNotifications
import ServiceManagement
import AppKit

enum NavSection: String, CaseIterable, Identifiable, Hashable {
    case home = "Home"
    case sandboxes = "Sandboxes"
    case environments = "Environments"
    case snapshots = "Snapshots"
    case webhooks = "Webhooks"
    case apiKeys = "API Keys"
    case account = "Account"
    case cli = "Console"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .sandboxes: return "shippingbox"
        case .environments: return "leaf"
        case .snapshots: return "camera.aperture"
        case .webhooks: return "antenna.radiowaves.left.and.right"
        case .apiKeys: return "key"
        case .account: return "person.crop.circle"
        case .cli: return "terminal"
        }
    }
    var filledIcon: String {
        switch self {
        case .snapshots, .webhooks: return icon
        default: return icon + ".fill"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .sandboxes: return "2"
        case .environments: return "3"
        case .snapshots: return "4"
        case .webhooks: return "5"
        case .apiKeys: return "6"
        case .account: return "7"
        case .cli: return "8"
        }
    }
    static let workspace: [NavSection] = [.home, .sandboxes, .environments, .snapshots]
    static let admin: [NavSection] = [.webhooks, .apiKeys, .account, .cli]
}

struct ActivityItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var sandboxId: String
    var name: String
    var from: String
    var to: String
}

enum ConnectionStatus: Equatable { case unknown, ok, failed(String) }

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    func go(_ s: NavSection) {
        AppearIn.pageOpened()
        withAnimation(BD.spring) {
            if s == .sandboxes && section == .sandboxes { selectedSandbox = nil }
            section = s
        }
    }
    // Connection
    @AppStorage("apiURL") var apiURL: String = "https://boat.dev/api/v1" { didSet { rebuildAPI() } }
    @AppStorage("org") var org: String = "" { didSet { rebuildAPI() } }
    @AppStorage("cliPath") var cliPathOverride: String = ""
    // General
    @AppStorage("refreshSeconds") var refreshSeconds: Double = 10
    @AppStorage("defaultSection") var defaultSection: NavSection = .home
    @AppStorage("skipConfirm") var skipConfirm: Bool = false
    // Notifications
    @AppStorage("notify") var notifyOnStateChange: Bool = true
    @AppStorage("notify.ready") var notifyReady: Bool = true
    @AppStorage("notify.error") var notifyError: Bool = true
    @AppStorage("notify.archived") var notifyArchived: Bool = false
    @AppStorage("notify.sound") var notifySound: Bool = true
    // New-sandbox defaults
    @AppStorage("new.type") var defaultType: String = "default"
    @AppStorage("new.ttlHours") var defaultTTLHours: Double = 1
    @AppStorage("new.environment") var defaultEnvironment: String = ""
    @AppStorage("new.openAfter") var openAfterCreate: Bool = true
    // Agent defaults
    @AppStorage("agent.provider") var agentProvider: String = ""
    @AppStorage("agent.model") var agentModel: String = ""
    @AppStorage("agent.effort") var agentEffort: String = ""
    @AppStorage("agent.expandTools") var expandTools: Bool = false

    @Published private(set) var apiKey: String = ""
    @Published private(set) var sessionID = UUID()
    @Published var section: NavSection = .home { didSet { if section != oldValue { AppearIn.pageOpened() } } }
    @Published var sandboxes: [Record] = []
    @Published var loadedOnce = false
    @Published var selectedSandbox: String? { didSet { if selectedSandbox != oldValue { AppearIn.pageOpened() } } }
    @Published var environments: [Record] = []
    @Published var namedSnapshots: [Record] = []
    @Published var me: JSON?
    @Published var limits: JSON?
    @Published var loading = false
    @Published var lastError: String?
    @Published var toasts: [Toast] = []
    @Published var showNewSandbox = false
    @Published var showPalette = false
    @Published var cliPath: String?
    @Published var connection: ConnectionStatus = .unknown
    @Published var activity: [ActivityItem] = []
    @Published var catalog: [String: [String]] = [:]
    @Published var efforts: [String: [String]] = [:]

    private(set) var api: BoatAPI
    private var pollTask: Task<Void, Never>?
    private var approvedCLIContext: String?
    private var lastStates: [String: String] = [:]

    init() {
        var stored: String?
        var storageError: String?
        do { stored = try Credentials.load() }
        catch { storageError = error.localizedDescription }
        let key = storageError == nil ? (stored ?? ProcessInfo.processInfo.environment["BOAT_API_KEY"] ?? "") : ""
        api = BoatAPI(baseURL: UserDefaults.standard.string(forKey: "apiURL") ?? "https://boat.dev/api/v1",
                      apiKey: key, org: UserDefaults.standard.string(forKey: "org"))
        apiKey = key
        section = NavSection(rawValue: UserDefaults.standard.string(forKey: "defaultSection") ?? "") ?? .home
        // Old activity was not scoped to an account. Keep activity in memory from now on.
        UserDefaults.standard.removeObject(forKey: "activity")
        relocateCLI()
        if let storageError { toast("Cannot read saved credentials: \(storageError)", error: true) }
        if stored == nil, key.isEmpty, storageError == nil {
            let initialSession = sessionID
            Task {
                let legacyKey = await Task.detached { Keychain.get("apiKey") }.value
                guard self.sessionID == initialSession, self.apiKey.isEmpty,
                      let legacyKey, !legacyKey.isEmpty else { return }
                if self.setAPIKey(legacyKey) {
                    await self.removeLegacyKey()
                    await self.refreshAll()
                }
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startPolling()
    }

    @discardableResult
    func setAPIKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try Credentials.save(key) }
        catch { toast("Could not save credentials: \(error.localizedDescription)", error: true); return false }
        apiKey = key
        rebuildAPI(force: true)
        return true
    }

    func signOut() async {
        // Save the empty marker first; do not claim success if persistence fails.
        guard setAPIKey("") else { return }
        UserDefaults.standard.removeObject(forKey: "term.history")
        UserDefaults.standard.removeObject(forKey: "term.cwd")
        await removeLegacyKey()
    }

    private func removeLegacyKey() async {
        let message = await Task.detached { () -> String? in
            do { try Keychain.remove("apiKey"); return nil }
            catch { return error.localizedDescription }
        }.value
        if let message { toast("Saved credential updated, but the old Keychain item could not be removed: \(message)", error: true) }
    }

    private func rebuildAPI(force: Bool = false) {
        guard force || api.baseURL != apiURL || api.apiKey != apiKey || api.org != (org.isEmpty ? nil : org) else { return }
        pollTask?.cancel()
        api.cancel()
        api = BoatAPI(baseURL: apiURL, apiKey: apiKey, org: org.isEmpty ? nil : org)
        sessionID = UUID()
        approvedCLIContext = nil
        sandboxes = []; environments = []; namedSnapshots = []
        me = nil; limits = nil; catalog = [:]; efforts = [:]; activity = []; lastStates = [:]
        loadedOnce = false; loading = false; lastError = nil; connection = .unknown
        selectedSandbox = nil; showNewSandbox = false; showPalette = false; toasts = []
        startPolling()
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var userName: String {
        let u = me?["user"] ?? me ?? .null
        return u.first("name", "login", "email")?.string ?? "there"
    }
    var userEmail: String? { (me?["user"] ?? me)?.first("email")?.string }

    func relocateCLI() {
        let override = cliPathOverride
        Task.detached {
            let p = BoatCLI.locate(override: override)
            await MainActor.run { [weak self] in self?.cliPath = p }
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.hasKey { await self.refreshSandboxes(silent: true) }
                let s = max(3, self.refreshSeconds)
                try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
            }
        }
    }

    func refreshAll() async {
        guard hasKey else { return }
        let client = api
        let generation = sessionID
        if !loading { loading = true }
        defer { if sessionID == generation, loading { loading = false } }
        await refreshSandboxes(silent: false)
        guard sessionID == generation, !Task.isCancelled else { return }
        async let e = try? client.environments()
        async let n = try? client.namedSnapshots()
        async let m = try? client.me()
        async let l = try? client.limits()
        let (ne, nn, nm, nl) = await (e, n, m, l)
        guard sessionID == generation, !Task.isCancelled else { return }
        if let ne, ne != environments { environments = ne }
        if let nn, nn != namedSnapshots { namedSnapshots = nn }
        if let nm, nm != me { me = nm }
        if let nl, nl != limits { limits = nl }
        if catalog.isEmpty { await loadCatalog() }
    }

    func testConnection() async {
        let client = api
        do {
            let result = try await client.me()
            guard api === client, !Task.isCancelled else { return }
            me = result; connection = .ok
        } catch {
            guard api === client, !Task.isCancelled else { return }
            connection = .failed(error.localizedDescription)
        }
    }

    func refreshSandboxes(silent: Bool) async {
        let client = api
        do {
            let list = try await client.sandboxes()
            guard api === client, !Task.isCancelled else { return }
            detectChanges(list)
            if list != sandboxes { withAnimation(BD.spring) { sandboxes = list } }
            if !loadedOnce { loadedOnce = true }
            if connection != .ok { connection = .ok }
            if !silent, lastError != nil { lastError = nil }
        } catch {
            guard api === client, !Task.isCancelled else { return }
            if !loadedOnce { loadedOnce = true }
            if !silent, lastError != error.localizedDescription { lastError = error.localizedDescription }
            if let e = error as? BoatError, e.status == 401 || e.status == 403 { connection = .failed(e.message) }
        }
    }

    private func detectChanges(_ list: [Record]) {
        var changed = false
        for s in list {
            let st = s.state
            if let old = lastStates[s.id], old != st {
                activity.insert(ActivityItem(date: Date(), sandboxId: s.id, name: s.displayName, from: old, to: st), at: 0)
                changed = true
                notify(s, from: old, to: st)
            } else if lastStates[s.id] == nil, loadedOnce {
                activity.insert(ActivityItem(date: Date(), sandboxId: s.id, name: s.displayName, from: "—", to: st), at: 0)
                changed = true
            }
            lastStates[s.id] = st
        }
        if changed {
            if activity.count > 200 { activity = Array(activity.prefix(200)) }
        }
    }

    private func notify(_ s: Record, from: String, to: String) {
        guard notifyOnStateChange else { return }
        let wanted = (["ready", "idle"].contains(to) && notifyReady)
            || (["error", "failed"].contains(to) && notifyError)
            || (["archived", "stopped"].contains(to) && notifyArchived)
        guard wanted else { return }
        let c = UNMutableNotificationContent()
        c.title = s.displayName
        c.body = "\(from.capitalized) → \(to.capitalized)"
        if notifySound { c.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func clearActivity() {
        activity = []
        UserDefaults.standard.removeObject(forKey: "activity")
    }

    func toast(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toasts.append(t)
        if toasts.count > 4 { toasts.removeFirst() }
        Task { try? await Task.sleep(nanoseconds: error ? 6_000_000_000 : 3_500_000_000); toasts.removeAll { $0.id == t.id } }
    }

    /// Runs an API action, reporting success/failure as a toast.
    @discardableResult
    func run(_ label: String, refresh: Bool = true, _ op: @escaping (BoatAPI) async throws -> JSON) async -> JSON? {
        let client = api
        do {
            let r = try await op(client)
            guard api === client, !Task.isCancelled else { return nil }
            toast(label)
            if refresh { await refreshSandboxes(silent: true) }
            return r
        } catch {
            guard api === client, !Task.isCancelled else { return nil }
            toast("\(label) failed — \(error.localizedDescription)", error: true)
            return nil
        }
    }

    /// A failed write is never retried with a different transport or credential.
    @discardableResult
    func runAction(_ label: String, _ op: @escaping (BoatAPI) async throws -> JSON) async -> Bool {
        await run(label, refresh: false, op) != nil
    }

    /// CLI sessions are independent of API keys. Require an explicit account choice before using one.
    func prepareCLI(_ args: [String]) async -> (String, [String])? {
        guard let binary = cliPath else { toast("boat CLI not found — set it up in Settings › CLI", error: true); return nil }
        let generation = sessionID
        let client = api
        do {
            // Validate the endpoint before passing it to another client.
            _ = try client.makeRequest("GET", "/me")
            let info = try await client.limits()
            guard sessionID == generation, !Task.isCancelled else { return nil }
            let wallet = client.org ?? info["teamId"]?.string ?? "personal"
            let context = CLIContext(apiURL: client.baseURL, organization: wallet)
            let status = await BoatCLI.run(binary, context.arguments + ["status", "--json"], timeout: 15)
            guard sessionID == generation, !Task.isCancelled else { return nil }
            guard status.exitCode == 0,
                  let identifier = status.json?["account"]?["identifier"]?.string, !identifier.isEmpty,
                  status.json?["account"]?["loginState"]?.string != "signed out" else {
                toast("Sign in to the boat CLI in Settings › CLI before using CLI actions.", error: true)
                return nil
            }
            let fingerprint = [binary, identifier, context.endpoint, wallet].joined(separator: "\n")
            if approvedCLIContext != fingerprint {
                let alert = NSAlert()
                alert.messageText = "Use this CLI account?"
                alert.informativeText = "CLI account: \(identifier)\nApp account: \(userEmail ?? userName)\nServer: \(context.endpoint)\nWallet: \(wallet)\n\nThe CLI uses its own saved login. This choice lasts until you switch accounts or restart Boat Deck."
                alert.addButton(withTitle: "Use CLI account")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }
                approvedCLIContext = fingerprint
            }
            return (binary, context.arguments + args)
        } catch {
            if sessionID == generation { toast("Could not prepare CLI context: \(error.localizedDescription)", error: true) }
            return nil
        }
    }

    func openCLI(_ args: [String]) {
        Task {
            guard let (binary, arguments) = await prepareCLI(args) else { return }
            BoatCLI.openInTerminal(binary, arguments)
        }
    }

    @discardableResult
    func cli(_ label: String, _ args: [String]) async -> CLIResult? {
        let generation = sessionID
        guard let (binary, arguments) = await prepareCLI(args) else { return nil }
        let result = await BoatCLI.run(binary, arguments)
        guard sessionID == generation, !Task.isCancelled else { return nil }
        if result.exitCode == 0 { toast(label) }
        else { toast("\(label) failed — \((result.stderr + result.stdout).prefix(240))", error: true) }
        return result
    }

    // MARK: Sandbox helpers

    func quickLaunch() async {
        var b: [String: JSON] = ["type": .string(defaultType), "ttlSeconds": .number((defaultTTLHours * 3600).rounded())]
        if !defaultEnvironment.isEmpty { b["environment"] = .string(defaultEnvironment) }
        if let r = await run("Sandbox launching", { try await $0.createSandbox(.object(b)) }),
           let id = (r["sandbox"] ?? r).first("id", "sandboxId")?.string, openAfterCreate {
            open(sandbox: id)
        }
    }

    func open(sandbox id: String) {
        AppearIn.pageOpened()
        withAnimation(BD.spring) {
            section = .sandboxes
            selectedSandbox = id
        }
    }

    func loadCatalog() async {
        let client = api
        let result = try? await client.providerModels()
        guard api === client, !Task.isCancelled else { return }
        guard let j = result else {
            if catalog.isEmpty { catalog = ["claude-code": [], "codex": []] }
            return
        }
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

    var runningCount: Int { sandboxes.filter { $0.isActive }.count }

    /// (running, limit) for concurrently active sandboxes.
    var concurrency: (Double, Double?) {
        let l = limits
        let running = l?["activeSandboxes"]?.double ?? l?["concurrency"]?["running"]?.double ?? Double(runningCount)
        let limit = l?["maxActiveSandboxes"]?.double ?? l?["currentLimits"]?["activeSandboxes"]?.double ?? l?["concurrency"]?["limit"]?.double
        return (running, limit)
    }

    var creditHours: Double? {
        if let h = limits?.first("creditBalanceHours")?.double { return h }
        if let s = limits?.first("creditBalanceSeconds")?.double { return s / 3600 }
        return nil
    }

    // MARK: Launch at login
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { toast("Launch at login: \(error.localizedDescription)", error: true) }
            objectWillChange.send()
        }
    }
}

extension Record {
    var state: String { self["state", "status"] ?? "unknown" }
    var displayName: String { self["name", "title"] ?? id }
    var stateColor: Color { colorForState(state) }
    var isActive: Bool { ["ready", "running", "idle", "provisioning", "provisioned", "cloning", "hydrating", "resuming"].contains(state) }
    var isArchived: Bool { ["archived", "stopped", "paused"].contains(state) }
    var machineType: String { self["machineType", "type", "size"] ?? "default" }
    var specs: String {
        if let c = json["vcpu"]?.int, let m = json["memoryGB"]?.int { return "\(c) vCPU · \(m) GB" }
        switch machineType {
        case "default": return "4 vCPU · 8 GB"
        default: return machineType.capitalized
        }
    }
    /// When the sandbox will auto-stop (archive), if it has a deadline.
    var archiveAfter: Date? { Date.fromISO(self["archiveAfter", "expiresAt", "autoStopAt"]) }
}
