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
        if let index = arguments.firstIndex(of: "--screenshots"), arguments.count > index + 1 {
            do { try Screenshots.write(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true)) }
            catch { fputs("Screenshot rendering failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
            return
        }
        store = QuotaStore(demo: arguments.contains("--demo"))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: QuotaPopover(store: store))
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
        let image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "CliProxy remaining quota")
        image?.isTemplate = true
        button.image = image
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
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Render the actual native views with synthetic data, without capturing the user's desktop.
@MainActor enum Screenshots {
    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, tab, settings, dark) in [
            ("overview", "All accounts", false, false),
            ("accounts", "Per account", false, false),
            ("settings", "All accounts", true, false),
            ("overview-dark", "All accounts", false, true)
        ] {
            let store = QuotaStore(demo: true)
            store.selectedView = tab; store.showSettings = settings
            let view = QuotaPopover(store: store, expandedInitially: tab == "Per account" ? ["demo-codex-1"] : []).environment(\.colorScheme, dark ? .dark : .light)
            let controller = NSHostingController(rootView: view)
            let fitting = controller.view.fittingSize
            let size = NSSize(width: 390, height: max(200, fitting.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentViewController = controller
            window.setContentSize(size)
            controller.view.frame = NSRect(origin: .zero, size: size)
            window.orderFrontRegardless()
            controller.view.layoutSubtreeIfNeeded()
            // Give AppKit a layout/display pass before reading the native backing store.
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent("\(name).png"))
            window.orderOut(nil)
        }
    }
}
