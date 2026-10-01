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

@main
struct BoatDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()
    @ObservedObject private var prefs = UIPrefs.shared

    var body: some Scene {
        WindowGroup("Boat Deck", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .tint(prefs.accent.color)
                .preferredColorScheme(prefs.theme.scheme)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sandbox…") { state.showNewSandbox = true }
                    .keyboardShortcut("n")
                Button("Quick Launch Sandbox") { Task { await state.quickLaunch() } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(prefs.sidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar") {
                    withAnimation(BD.spring) { prefs.sidebarCollapsed.toggle() }
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
            CommandMenu("Go") {
                Button("Command Palette…") { state.showPalette.toggle() }.keyboardShortcut("k")
                Button("Refresh") { Task { await state.refreshAll() } }.keyboardShortcut("r")
                Divider()
                ForEach(NavSection.allCases) { s in
                    Button(s.rawValue) { withAnimation(BD.spring) { state.section = s } }
                        .keyboardShortcut(s.shortcut)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(prefs)
                .tint(prefs.accent.color)
                .preferredColorScheme(prefs.theme.scheme)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(isInserted: $prefs.showMenuBar) {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(prefs)
                .tint(prefs.accent.color)
        } label: {
            Image(systemName: state.runningCount > 0 ? "sailboat.fill" : "sailboat")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Makes the hosting window movable by its background and transparent-titled.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.backgroundColor = .clear
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
