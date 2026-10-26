import AppKit
import QuotaCore

enum MenuBarAppearance {
    // Dark gold and red keep white text readable against the warning fills.
    static let warningBackground = NSColor(srgbRed: 0.60, green: 0.43, blue: 0, alpha: 1)
    static let criticalBackground = NSColor(srgbRed: 0.70, green: 0.10, blue: 0.08, alpha: 1)
    static func title(for readout: MenuBarReadout, mode: PercentageMode, window: MenuBarWindow,
                      includeSource: Bool = false) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let text = NSMutableAttributedString(string: " ", attributes: normal)
        if includeSource { text.append(NSAttributedString(string: readout.title + " ", attributes: normal)) }
        func append(_ remaining: Double?, label: String = "") {
            let value = label + (remaining.map { mode.formatted($0) } ?? "—")
            let severity = TrayQuotaSeverity.forRemaining(remaining)
            guard severity != .normal else {
                text.append(NSAttributedString(string: value, attributes: normal)); return
            }
            text.append(NSAttributedString(string: " ", attributes: normal))
            text.append(NSAttributedString(string: "  " + value + "  ", attributes: [
                .font: font, .foregroundColor: NSColor.white,
                .backgroundColor: severity == .warning ? warningBackground : criticalBackground
            ]))
            text.append(NSAttributedString(string: " ", attributes: normal))
        }
        switch window {
        case .fiveHour: append(readout.fiveHour)
        case .weekly: append(readout.weekly)
        case .both:
            append(readout.fiveHour, label: "⁵ʰ ")
            text.append(NSAttributedString(string: " · ", attributes: normal))
            append(readout.weekly, label: "ʷ ")
        }
        return text
    }
}
