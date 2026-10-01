import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UIPrefs.shared.apply()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !UIPrefs.shared.showMenuBar }
}

/// Scene-level code deliberately observes nothing: the shared objects are handed to views, which observe them.
/// (Observing @Published state at the App level makes SwiftUI rebuild every scene on each poll.)
@main
struct BoatDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("ui.menuBar") private var showMenuBar = true
    private let state = AppState.shared
    private let prefs = UIPrefs.shared

    var body: some Scene {
        WindowGroup("Boat Deck", id: "main") {
            Themed { RootView().frame(minWidth: 720, minHeight: 540) }
                .environmentObject(state)
                .environmentObject(prefs)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sandbox…") { state.showNewSandbox = true }
                    .keyboardShortcut("n")
                Button("Quick Launch Sandbox") { Task { await state.quickLaunch() } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Command Palette…") { state.showPalette.toggle() }.keyboardShortcut("k")
                Button("Refresh") { Task { await state.refreshAll() } }.keyboardShortcut("r")
                Button("Toggle Sidebar") { withAnimation(BD.spring) { prefs.sidebarCollapsed.toggle() } }
                    .keyboardShortcut("\\")
                Divider()
                Button("Home") { state.go(.home) }.keyboardShortcut("1")
                Button("Sandboxes") { state.go(.sandboxes) }.keyboardShortcut("2")
                Button("Environments") { state.go(.environments) }.keyboardShortcut("3")
                Button("Snapshots") { state.go(.snapshots) }.keyboardShortcut("4")
                Button("Webhooks") { state.go(.webhooks) }.keyboardShortcut("5")
                Button("API Keys") { state.go(.apiKeys) }.keyboardShortcut("6")
                Button("Account") { state.go(.account) }.keyboardShortcut("7")
                Button("Console") { state.go(.cli) }.keyboardShortcut("8")
            }
        }

        Settings {
            Themed { SettingsView() }
                .environmentObject(state)
                .environmentObject(prefs)
        }
        .windowStyle(.hiddenTitleBar)

        // Only write when the value really changes: MenuBarExtra re-asserts its binding on every update, and an
        // unconditional @AppStorage write fires a UserDefaults notification → re-render → write … (busy loop).
        MenuBarExtra(isInserted: Binding(get: { showMenuBar }, set: { if $0 != showMenuBar { showMenuBar = $0 } })) {
            Themed { MenuBarView() }
                .environmentObject(state)
                .environmentObject(prefs)
        } label: {
            MenuBarLabel().environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Applies the accent tint from preferences (appearance itself is applied app-wide via NSApp.appearance).
struct Themed<Content: View>: View {
    @ObservedObject var prefs = UIPrefs.shared
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().tint(prefs.accent.color)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Image(systemName: state.runningCount > 0 ? "sailboat.fill" : "sailboat")
    }
}
