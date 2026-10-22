import AppKit
import SwiftUI
import QuotaCore

/// One clipped background keeps segment boundaries square and outer corners rounded.
struct SettingsSegments<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Button { selection = value } label: {
                    Text(title(value))
                        .font(.system(size: 11, weight: selection == value ? .medium : .regular))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity).frame(height: 25)
                        .background(selection == value ? Color.primary.opacity(0.13) : Color.clear)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize(horizontal: false, vertical: true)
    }
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
        button.menu = menu(coordinator: context.coordinator, dark: button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 380, height: nsView.intrinsicContentSize.height)
    }
    func menu(coordinator: SourceCoordinator, dark: Bool = false) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: summary, action: nil, keyEquivalent: "")
        func heading(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }
        func add(_ id: String, _ title: String, provider: String? = nil) {
            let item = NSMenuItem(title: title, action: #selector(SourceCoordinator.toggle(_:)), keyEquivalent: "")
            item.target = coordinator; item.representedObject = id
            if let provider { item.image = ProviderArtwork.menuImage(for: provider, dark: dark) }
            item.state = selectedIDs.contains(id) ? .on : .off
            menu.addItem(item)
        }
        heading("PROVIDER AVERAGES")
        for source in sources.filter(\.isProvider) { add(source.id, "\(source.title) · \(source.detail)", provider: source.provider) }
        menu.addItem(.separator())
        heading("INDIVIDUAL ACCOUNTS")
        for source in sources.filter({ !$0.isProvider }) { add(source.id, "\(source.title) · \(source.detail)", provider: source.provider) }
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
