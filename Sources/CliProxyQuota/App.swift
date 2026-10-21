import AppKit
import SwiftUI
import QuotaCore

@main struct CliProxyQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private var store: QuotaStore!
    private var statusTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--verify-layout") {
            Task { @MainActor in
                do { try await Screenshots.verifyLayout() }
                catch { fputs("Layout verification failed: \(error)\n", stderr); exit(1) }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = arguments.firstIndex(of: "--screenshots"), arguments.count > index + 1 {
            Task { @MainActor in
                do { try await Screenshots.write(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true)) }
                catch { fputs("Screenshot rendering failed: \(error)\n", stderr); exit(1) }
                NSApp.terminate(nil)
            }
            return
        }
        store = QuotaStore(demo: arguments.contains("--demo"))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let controller = NSHostingController(rootView: QuotaPopover(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        NotificationCenter.default.addObserver(self, selector: #selector(updateScreenLimit),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
        store.start()
        if !store.configured && !store.demo { togglePopover() }
        if arguments.contains("--show") { togglePopover() }
    }
    private func updateStatus() {
        guard let button = item.button else { return }
        button.image = QuotaBotIcon.menuBar
        button.imagePosition = .imageLeading
        if store.demo { button.title = " Demo" }
        else if store.showPercentage {
            button.title = store.menuValue.map { " \(Int($0.rounded()))%" } ?? " —"
        } else { button.title = "" }
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = store.demo ? "CliProxy Quota · sample data" : store.issue ?? (store.menuValue == nil ? "CliProxy Quota · waiting for data" : "CliProxy remaining usage · click for accounts")
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            // visibleFrame excludes the menu bar and Dock on the display hosting the tray item.
            updateScreenLimit()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    @objc private func updateScreenLimit() {
        let screen = item.button?.window?.screen ?? NSScreen.main
        store.maximumPopoverHeight = (screen?.visibleFrame.height ?? 800) - 24
    }
}

/// Render the actual native views with synthetic data, without capturing the user's desktop.
@MainActor enum Screenshots {
    static func write(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, tab, settings, dark) in [
            ("overview", "All accounts", false, false),
            ("accounts", "Per account", false, false),
            ("settings", "All accounts", true, false),
            ("overview-dark", "All accounts", false, true)
        ] {
            let store = QuotaStore(demo: true)
            store.selectedView = tab; store.showSettings = settings
            let controller = NSHostingController(rootView: QuotaPopover(store: store,
                expandedInitially: tab == "Per account" ? ["demo-codex-1"] : [])
                .environment(\.colorScheme, dark ? .dark : .light))
            let window = await prepare(controller, dark: dark)
            guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent("\(name).png"))
            window.orderOut(nil)
        }
    }
    private static func prepare<V: View>(_ controller: NSHostingController<V>, dark: Bool = false) async -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 390, height: 600)
        window.orderFrontRegardless()
        await settle(controller, window: window)
        return window
    }
    private static func settle<V: View>(_ controller: NSHostingController<V>, window: NSWindow) async {
        // Let content and chrome measurements settle, including after account expansion or tab changes.
        for _ in 0..<5 {
            controller.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(80))
            let height = controller.view.fittingSize.height
            window.setContentSize(NSSize(width: 390, height: max(1, height)))
            controller.view.frame = NSRect(x: 0, y: 0, width: 390, height: max(1, height))
        }
        controller.view.layoutSubtreeIfNeeded()
    }
    static func verifyLayout() async throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "PopoverLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        for tab in ["All accounts", "Per account"] {
            let store = QuotaStore(demo: true)
            store.maximumPopoverHeight = 1200
            store.selectedView = tab
            let controller = NSHostingController(rootView: QuotaPopover(store: store,
                expandedInitially: Set(store.quotas.map(\.id))))
            let window = await prepare(controller)
            let natural = controller.view.fittingSize.height
            try check(natural > 500 && natural < 1200, "\(tab) must fit full expanded content on a tall display: \(natural)")
            store.maximumPopoverHeight = 500
            await settle(controller, window: window)
            let capped = controller.view.fittingSize.height
            try check(abs(capped - 500) < 2, "\(tab) must scroll at the screen boundary: \(capped)")
            store.maximumPopoverHeight = 1200
            await settle(controller, window: window)
            let restored = controller.view.fittingSize.height
            try check(abs(restored - natural) < 2, "\(tab) must grow back when more screen space is available")
            // Changing tabs must remeasure the chrome as well as the list.
            store.selectedView = tab == "All accounts" ? "Per account" : "All accounts"
            await settle(controller, window: window)
            let switched = controller.view.fittingSize.height
            try check(switched > 500 && switched < 1200, "Tab switch must retain natural content sizing")
            print("\(tab): full \(Int(natural))pt; capped \(Int(capped))pt; restored \(Int(restored))pt; tab switch \(Int(switched))pt")
            window.orderOut(nil)
        }
    }
}
