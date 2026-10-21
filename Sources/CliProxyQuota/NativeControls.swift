import AppKit
import SwiftUI
import QuotaCore

/// Explicit sizing keeps both segmented controls on the same right edge and width.
struct SettingsSegments<Value: Hashable>: NSViewRepresentable {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    func makeCoordinator() -> SegmentCoordinator { SegmentCoordinator() }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: values.map(title), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(SegmentCoordinator.select(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.selectedSegment = values.firstIndex(of: selection) ?? 0
        context.coordinator.onSelect = { index in if values.indices.contains(index) { selection = values[index] } }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 216, height: nsView.intrinsicContentSize.height)
    }
}

final class SegmentCoordinator: NSObject {
    var onSelect: (Int) -> Void = { _ in }
    @objc func select(_ sender: NSSegmentedControl) { onSelect(sender.selectedSegment) }
}

struct SourceMenuButton: NSViewRepresentable {
    let summary: String
    let sources: [MenuBarSource]
    let selectedIDs: [String]
    let onToggle: (String) -> Void
    func makeCoordinator() -> SourceCoordinator { SourceCoordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("Menu bar source")
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onToggle = onToggle
        button.menu = menu(coordinator: context.coordinator)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 380, height: nsView.intrinsicContentSize.height)
    }
    func menu(coordinator: SourceCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: summary, action: nil, keyEquivalent: "")
        func heading(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }
        func add(_ id: String, _ title: String) {
            let item = NSMenuItem(title: title, action: #selector(SourceCoordinator.toggle(_:)), keyEquivalent: "")
            item.target = coordinator; item.representedObject = id
            item.state = selectedIDs.contains(id) ? .on : .off
            menu.addItem(item)
        }
        heading("PROVIDER AVERAGES")
        for source in sources.filter(\.isProvider) { add(source.id, "\(source.title) · \(source.detail)") }
        menu.addItem(.separator())
        heading("INDIVIDUAL ACCOUNTS")
        for source in sources.filter({ !$0.isProvider }) { add(source.id, "\(source.title) · \(source.detail)") }
        for id in selectedIDs where !sources.contains(where: { $0.id == id }) { add(id, "Unavailable source") }
        if sources.isEmpty { heading("Connect to load accounts") }
        return menu
    }
}

final class SourceCoordinator: NSObject {
    var onToggle: (String) -> Void = { _ in }
    @objc func toggle(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onToggle(id) }
    }
}
