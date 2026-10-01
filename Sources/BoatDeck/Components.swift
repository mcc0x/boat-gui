import SwiftUI
import AppKit

struct StateBadge: View {
    let state: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(colorForState(state)).frame(width: 8, height: 8)
            Text(state).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(colorForState(state).opacity(0.14), in: Capsule())
    }
}

struct KV: View {
    let key: String
    let value: String?
    var mono = false
    var body: some View {
        GridRow {
            Text(key).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            HStack(spacing: 4) {
                Text(value ?? "—")
                    .font(mono ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .lineLimit(2)
                if let value, !value.isEmpty {
                    Button { copyToClipboard(value) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy")
                }
            }
            .gridColumnAlignment(.leading)
        }
    }
}

/// Generic key/value renderer for any JSON object — ensures every field Boat returns is visible.
struct JSONGrid: View {
    let json: JSON
    var skip: Set<String> = ["ok", "type"]
    var body: some View {
        if let o = json.object {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(o.keys.sorted().filter { !skip.contains($0) }, id: \.self) { k in
                    let v = o[k]!
                    if let s = v.string {
                        KV(key: k, value: s, mono: k.lowercased().contains("id"))
                    } else {
                        GridRow {
                            Text(k).foregroundStyle(.secondary)
                            Text(v.compact).font(.system(.caption, design: .monospaced)).lineLimit(3).textSelection(.enabled)
                        }
                    }
                }
            }
        } else {
            Text(json.pretty).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
}

struct RawJSONButton: View {
    let json: JSON?
    @VState private var show = false
    var body: some View {
        Button { show = true } label: { Label("Raw JSON", systemImage: "curlybraces") }
            .disabled(json == nil)
            .popover(isPresented: $show) {
                ScrollView {
                    Text(json?.pretty ?? "").font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 520, height: 460)
            }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String = ""
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastOverlay: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(state.toasts) { t in
                HStack(spacing: 8) {
                    Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.isError ? .red : .green)
                    Text(t.text).lineLimit(3)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.toasts)
        .padding()
        .frame(maxWidth: 420)
    }
}

/// Plain monospaced, scrollable log output that auto-scrolls.
struct LogView: View {
    let text: String
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

func confirm(_ title: String, _ message: String, destructive: String = "Delete") -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .warning
    a.addButton(withTitle: destructive)
    a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
}

func promptText(_ title: String, _ message: String = "", default def: String = "", ok: String = "OK") -> String? {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.addButton(withTitle: ok)
    a.addButton(withTitle: "Cancel")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    tf.stringValue = def
    a.accessoryView = tf
    a.window.initialFirstResponder = tf
    return a.runModal() == .alertFirstButtonReturn ? tf.stringValue : nil
}

func showSecret(_ title: String, _ secret: String) {
    copyToClipboard(secret)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = "Copied to the clipboard. It won't be shown again:\n\n\(secret)"
    a.runModal()
}

/// On the macOS 27 SDK `@State` is a macro whose plugin ships only with full Xcode.
/// Referring to the property-wrapper type through a typealias sidesteps the macro so
/// the app also builds with just the Command Line Tools.
typealias VState = SwiftUI.State
