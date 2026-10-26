import AppKit
import QuotaCore

enum MenuBarAppearance {
    static func title(for readout: MenuBarReadout, mode: PercentageMode, window: MenuBarWindow,
                      includeSource: Bool = false) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let text = NSMutableAttributedString(string: " ", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        for part in readout.parts(mode: mode, window: window, includeSource: includeSource) {
            let color: NSColor
            switch part.severity {
            case .normal: color = .labelColor
            case .warning: color = .systemYellow
            case .critical: color = .systemRed
            }
            text.append(NSAttributedString(string: part.text, attributes: [.font: font, .foregroundColor: color]))
        }
        return text
    }
}
