import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct BoatDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Boat Deck", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Sandbox…") { state.showNewSandbox = true; state.section = .sandboxes }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Boat") {
                Button("Refresh") { Task { await state.refreshAll() } }.keyboardShortcut("r")
                Divider()
                ForEach(NavSection.allCases) { s in
                    Button(s.rawValue) { state.section = s }
                }
            }
        }

        Settings {
            SettingsView().environmentObject(state)
        }

        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            Label("\(state.runningCount)", systemImage: "sailboat")
        }
        .menuBarExtraStyle(.window)
    }
}
