import AppKit
import SwiftUI
import Combine

@main
struct FocusIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: FocusModel!
    private var statusItem: NSStatusItem!
    private var island: NSPanel!
    private var window: NSWindow!
    private var expanded = false
    private var changingIslandLayout = false
    private var placementSave: DispatchWorkItem?
    private var consentPanel: NSPanel?
    private var consentObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let flag = CommandLine.arguments.firstIndex(of: "--export-screenshots"), CommandLine.arguments.indices.contains(flag + 1) {
            let destination = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
            Task { @MainActor in
                do { try await ScreenshotExporter.write(to: destination) }
                catch { FileHandle.standardError.write(Data("Screenshot export failed: \(error.localizedDescription)\n".utf8)) }
                NSApp.terminate(nil)
            }
            return
        }
        model = FocusModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Focus Island")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open dashboard", action: #selector(openDashboard), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "Show / hide island", action: #selector(toggleIsland), keyEquivalent: "i").target = self
        menu.addItem(withTitle: "Pause / resume tracking", action: #selector(togglePause), keyEquivalent: "p").target = self
        menu.addItem(withTitle: "Reset island position and size", action: #selector(resetIsland), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Focus Island", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        island = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        island.delegate = self
        island.level = .floating
        island.backgroundColor = .clear
        island.isOpaque = false
        island.hasShadow = true
        island.isMovable = true
        island.isMovableByWindowBackground = true
        island.hidesOnDeactivate = false
        island.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        updateIsland()
        island.orderFrontRegardless()
        model.showSummary = { [weak self] in self?.expanded = true; self?.updateIsland(); self?.island.orderFrontRegardless() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        openDashboard()
        consentObservation = model.$requestedEditor.sink { [weak self] editor in
            self?.showConsent(editor)
        }
    }
    private func showConsent(_ editor: EditorSession?) {
        guard let editor else { consentPanel?.orderOut(nil); return }
        if consentPanel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Start a focus session"
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            consentPanel = panel
        }
        let size = NSSize(width: 420, height: 255)
        let screen = island.screen ?? NSScreen.main ?? NSScreen.screens.first!
        consentPanel?.contentView = NSHostingView(rootView: SessionConsentView(editor: editor, choose: { [weak self] allow in
            self?.model.respondToConsent(editor, allow: allow)
        }))
        consentPanel?.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: island.frame.minY - size.height - 12, width: size.width, height: size.height), display: true)
        consentPanel?.orderFrontRegardless()
    }
    private func clamped(_ rect: NSRect, to screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let width = min(rect.width, area.width)
        let height = min(rect.height, area.height)
        return NSRect(x: min(max(rect.minX, area.minX), area.maxX - width), y: min(max(rect.minY, area.minY), area.maxY - height), width: width, height: height)
    }
    private func updateIsland() {
        changingIslandLayout = true
        defer { changingIslandLayout = false }
        let preferences = UserDefaults.standard
        let key = expanded ? "expanded" : "collapsed"
        let width = preferences.double(forKey: "island.\(key).width")
        let height = preferences.double(forKey: "island.expanded.height")
        let size = NSSize(width: width > 0 ? width : (expanded ? 390 : 320), height: expanded ? (height > 0 ? height : 215) : 42)
        var center = island.frame.isEmpty ? NSPoint.zero : NSPoint(x: island.frame.midX, y: island.frame.maxY)
        if island.frame.isEmpty, preferences.object(forKey: "island.anchorX") != nil {
            center = NSPoint(x: preferences.double(forKey: "island.anchorX"), y: preferences.double(forKey: "island.anchorY"))
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: center.x, y: center.y - 10)) } ?? island.screen ?? NSScreen.main ?? NSScreen.screens.first!
        if center == .zero { center = NSPoint(x: screen.frame.midX, y: screen.visibleFrame.maxY - 10) }
        island.minSize = NSSize(width: expanded ? 360 : 290, height: expanded ? 205 : 42)
        island.maxSize = NSSize(width: 720, height: expanded ? 420 : 42)
        let boundedSize = NSSize(width: min(island.maxSize.width, max(island.minSize.width, size.width)), height: min(island.maxSize.height, max(island.minSize.height, size.height)))
        let rect = clamped(NSRect(x: center.x - boundedSize.width / 2, y: center.y - boundedSize.height, width: boundedSize.width, height: boundedSize.height), to: screen)
        island.contentView = NSHostingView(rootView: IslandView(model: model, expanded: expanded, toggle: { [weak self] in
            guard let self else { return }
            self.storeIslandLayout()
            self.expanded.toggle()
            self.updateIsland()
        }, dashboard: { [weak self] in self?.openDashboard() }))
        island.setFrame(rect, display: true, animate: false)
    }
    private func storeIslandLayout() {
        guard !changingIslandLayout, let island, !island.frame.isEmpty else { return }
        let key = expanded ? "expanded" : "collapsed"
        UserDefaults.standard.set(island.frame.midX, forKey: "island.anchorX")
        UserDefaults.standard.set(island.frame.maxY, forKey: "island.anchorY")
        UserDefaults.standard.set(island.frame.width, forKey: "island.\(key).width")
        if expanded { UserDefaults.standard.set(island.frame.height, forKey: "island.expanded.height") }
    }
    func windowDidMove(_ notification: Notification) { islandGeometryChanged(notification) }
    func windowDidResize(_ notification: Notification) { islandGeometryChanged(notification) }
    private func islandGeometryChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === island, !changingIslandLayout else { return }
        placementSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.storeIslandLayout() }
        placementSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    @objc private func resetIsland() {
        for key in ["island.anchorX", "island.anchorY", "island.collapsed.width", "island.expanded.width", "island.expanded.height"] { UserDefaults.standard.removeObject(forKey: key) }
        changingIslandLayout = true
        island.setFrame(.zero, display: false)
        changingIslandLayout = false
        updateIsland()
    }
    @objc private func screenChanged() { updateIsland(); showConsent(model.requestedEditor) }
    @objc private func toggleIsland() { if island.isVisible { island.orderOut(nil) } else { updateIsland(); island.orderFrontRegardless() } }
    @objc private func togglePause() { model.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func openDashboard() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Focus Island"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(Color.canvas)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Dashboard(model: model))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) { model?.save(); storeIslandLayout() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
