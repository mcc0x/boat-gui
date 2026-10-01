import Foundation
import SwiftUI
import UserNotifications
import ServiceManagement

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

    @Published var apiKey: String = "" { didSet { Keychain.set("apiKey", apiKey); rebuildAPI() } }
    @Published var section: NavSection = .home
    @Published var sandboxes: [Record] = []
    @Published var loadedOnce = false
    @Published var selectedSandbox: String?
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
    private var lastStates: [String: String] = [:]

    init() {
        let key = Keychain.get("apiKey") ?? ProcessInfo.processInfo.environment["BOAT_API_KEY"] ?? ""
        api = BoatAPI(baseURL: UserDefaults.standard.string(forKey: "apiURL") ?? "https://boat.dev/api/v1",
                      apiKey: key, org: UserDefaults.standard.string(forKey: "org"))
        apiKey = key
        section = NavSection(rawValue: UserDefaults.standard.string(forKey: "defaultSection") ?? "") ?? .home
        if let d = UserDefaults.standard.data(forKey: "activity"),
           let a = try? JSONDecoder().decode([ActivityItem].self, from: d) { activity = a }
        relocateCLI()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startPolling()
    }

    private func rebuildAPI() {
        api.baseURL = apiURL
        api.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        api.org = org.isEmpty ? nil : org
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

    private var probed = false
    /// With tracing on, hits every read-only endpoint once so their shapes land in the trace log.
    func probeIfTracing() async {
        guard Trace.enabled, !probed else { return }
        probed = true
        for p in ["/me", "/limits", "/orgs", "/sandboxes", "/environments", "/named-snapshots", "/snapshots",
                  "/webhooks", "/api-keys", "/provider-models", "/repos", "/secrets", "/account/data-retention"] {
            _ = try? await api.call("GET", p)
        }
    }

    func refreshAll() async {
        guard hasKey else { return }
        Task { await probeIfTracing() }
        loading = true
        defer { loading = false }
        await refreshSandboxes(silent: false)
        async let e = try? api.environments()
        async let n = try? api.namedSnapshots()
        async let m = try? api.me()
        async let l = try? api.limits()
        environments = await e ?? environments
        namedSnapshots = await n ?? namedSnapshots
        me = await m ?? me
        limits = await l ?? limits
        if catalog.isEmpty { await loadCatalog() }
    }

    func testConnection() async {
        do { me = try await api.me(); connection = .ok }
        catch { connection = .failed(error.localizedDescription) }
    }

    func refreshSandboxes(silent: Bool) async {
        do {
            let list = try await api.sandboxes()
            detectChanges(list)
            withAnimation(BD.spring) { sandboxes = list }
            loadedOnce = true
            connection = .ok
            if !silent { lastError = nil }
        } catch {
            loadedOnce = true
            if !silent { lastError = error.localizedDescription }
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
            if let d = try? JSONEncoder().encode(activity) { UserDefaults.standard.set(d, forKey: "activity") }
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
        do {
            let r = try await op(api)
            toast(label)
            if refresh { await refreshSandboxes(silent: true) }
            return r
        } catch {
            toast("\(label) failed — \(error.localizedDescription)", error: true)
            return nil
        }
    }

    /// Tries the REST API first; if that fails and the CLI is installed, runs the equivalent `boat` command.
    @discardableResult
    func runOrCLI(_ label: String, cli: [String], _ op: @escaping (BoatAPI) async throws -> JSON) async -> Bool {
        do {
            _ = try await op(api)
            toast(label)
            return true
        } catch {
            guard let p = cliPath else {
                toast("\(label) failed — \(error.localizedDescription)", error: true)
                return false
            }
            let r = await BoatCLI.run(p, cli)
            if r.exitCode == 0 { toast("\(label) (via CLI)"); return true }
            toast("\(label) failed — \(error.localizedDescription) · CLI: \((r.stderr + r.stdout).prefix(200))", error: true)
            return false
        }
    }

    /// Runs a boat CLI command and toasts the outcome.
    @discardableResult
    func cli(_ label: String, _ args: [String]) async -> CLIResult? {
        guard let p = cliPath else { toast("boat CLI not found — set it up in Settings › CLI", error: true); return nil }
        let r = await BoatCLI.run(p, args)
        if r.exitCode == 0 { toast(label) } else { toast("\(label) failed — \((r.stderr + r.stdout).prefix(240))", error: true) }
        return r
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
        withAnimation(BD.spring) {
            section = .sandboxes
            selectedSandbox = id
        }
    }

    func loadCatalog() async {
        guard let j = try? await api.providerModels() else { return }
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
    var isActive: Bool { ["ready", "running", "idle", "provisioning", "hydrating", "resuming"].contains(state) }
    var isArchived: Bool { ["archived", "stopped", "paused"].contains(state) }
    var machineType: String { self["machineType", "type", "size"] ?? "default" }
    var specs: String {
        switch machineType {
        case "default": return "4 vCPU · 8 GB"
        default: return machineType.capitalized
        }
    }
}
