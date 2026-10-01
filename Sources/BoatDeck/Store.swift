import Foundation
import SwiftUI
import UserNotifications

enum NavSection: String, CaseIterable, Identifiable, Hashable {
    case sandboxes = "Sandboxes"
    case environments = "Environments"
    case snapshots = "Snapshots"
    case webhooks = "Webhooks"
    case apiKeys = "API Keys"
    case account = "Account & Billing"
    case cli = "CLI Console"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .sandboxes: return "shippingbox"
        case .environments: return "leaf"
        case .snapshots: return "camera.aperture"
        case .webhooks: return "antenna.radiowaves.left.and.right"
        case .apiKeys: return "key"
        case .account: return "person.crop.circle"
        case .cli: return "terminal"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor
final class AppState: ObservableObject {
    @AppStorage("apiURL") var apiURL: String = "https://boat.dev/api/v1" { didSet { rebuildAPI() } }
    @AppStorage("org") var org: String = "" { didSet { rebuildAPI() } }
    @AppStorage("cliPath") var cliPathOverride: String = ""
    @AppStorage("refreshSeconds") var refreshSeconds: Double = 10
    @AppStorage("notify") var notifyOnStateChange: Bool = true

    @Published var apiKey: String = "" { didSet { Keychain.set("apiKey", apiKey); rebuildAPI() } }
    @Published var section: NavSection? = .sandboxes
    @Published var sandboxes: [Record] = []
    @Published var selectedSandbox: String?
    @Published var environments: [Record] = []
    @Published var namedSnapshots: [Record] = []
    @Published var me: JSON?
    @Published var limits: JSON?
    @Published var loading = false
    @Published var lastError: String?
    @Published var toasts: [Toast] = []
    @Published var showNewSandbox = false
    @Published var cliPath: String?

    private(set) var api: BoatAPI
    private var pollTask: Task<Void, Never>?
    private var lastStates: [String: String] = [:]

    init() {
        let key = Keychain.get("apiKey") ?? ProcessInfo.processInfo.environment["BOAT_API_KEY"] ?? ""
        api = BoatAPI(baseURL: UserDefaults.standard.string(forKey: "apiURL") ?? "https://boat.dev/api/v1",
                      apiKey: key, org: UserDefaults.standard.string(forKey: "org"))
        apiKey = key
        let override = cliPathOverride
        Task.detached { [weak self] in
            let p = BoatCLI.locate(override: override)
            await MainActor.run { self?.cliPath = p }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startPolling()
    }

    private func rebuildAPI() {
        api.baseURL = apiURL
        api.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        api.org = org.isEmpty ? nil : org
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func relocateCLI() {
        let override = cliPathOverride
        Task.detached { [weak self] in
            let p = BoatCLI.locate(override: override)
            await MainActor.run { self?.cliPath = p }
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
    }

    func refreshSandboxes(silent: Bool) async {
        do {
            let list = try await api.sandboxes()
            detectChanges(list)
            sandboxes = list
            if !silent { lastError = nil }
        } catch {
            if !silent { lastError = error.localizedDescription }
        }
    }

    private func detectChanges(_ list: [Record]) {
        for s in list {
            let st = s.state
            if let old = lastStates[s.id], old != st, notifyOnStateChange {
                let c = UNMutableNotificationContent()
                c.title = "Boat · \(s.displayName)"
                c.body = "\(old) → \(st)"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            }
            lastStates[s.id] = st
        }
    }

    func toast(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toasts.append(t)
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); toasts.removeAll { $0.id == t.id } }
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
        guard let p = cliPath else { toast("boat CLI not found — set its path in Settings", error: true); return nil }
        let r = await BoatCLI.run(p, args)
        if r.exitCode == 0 { toast(label) } else { toast("\(label) failed — \((r.stderr + r.stdout).prefix(240))", error: true) }
        return r
    }

    var runningCount: Int { sandboxes.filter { ["ready", "running", "idle", "provisioning"].contains($0.state) }.count }
}

extension Record {
    var state: String { self["state", "status"] ?? "unknown" }
    var displayName: String { self["name", "title"] ?? id }
    var stateColor: Color { colorForState(state) }
}

func colorForState(_ s: String) -> Color {
    switch s {
    case "ready", "idle": return .green
    case "running": return .blue
    case "provisioning", "hydrating", "resuming", "archiving", "stopping": return .orange
    case "archived", "stopped", "paused": return .gray
    case "error", "failed": return .red
    default: return .secondary
    }
}
