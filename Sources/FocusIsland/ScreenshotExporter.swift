import AppKit
import SwiftUI

/// Render the actual application views with isolated, illustrative data.
/// This path starts no activity monitors, Git commands, SSH connections, or preference writes.
@MainActor
enum ScreenshotExporter {
    static func write(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = FocusModel(preview: true)
        try await render(Dashboard(model: model), size: NSSize(width: 1080, height: 920), to: directory.appendingPathComponent("dashboard.png"))
        try await render(IslandView(model: model, expanded: false, toggle: {}, dashboard: {}), size: NSSize(width: 320, height: 42), to: directory.appendingPathComponent("island-compact.png"))
        try await render(IslandView(model: model, expanded: true, toggle: {}, dashboard: {}), size: NSSize(width: 390, height: 215), to: directory.appendingPathComponent("island-expanded.png"))
        model.connected = false
        model.login = ""
        try await render(SettingsView(model: model), size: NSSize(width: 530, height: 720), to: directory.appendingPathComponent("setup.png"))
        try await render(SettingsView(model: model, showEditors: true), size: NSSize(width: 530, height: 720), to: directory.appendingPathComponent("editors.png"))
        try await render(SessionConsentView(editor: EditorSession(id: 1, name: "VS Code"), choose: { _ in }), size: NSSize(width: 420, height: 255), to: directory.appendingPathComponent("session-consent.png"))
        print("Exported six interface screenshots with demo data to \(directory.path)")
    }
    private static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let view = NSHostingView(rootView: root)
        window.contentView = view
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        window.display()
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ServiceError(message: "Could not create a screenshot bitmap.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ServiceError(message: "Could not encode screenshot PNG.") }
        try png.write(to: url, options: .atomic)
        window.close()
    }
}
