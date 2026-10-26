import AppKit
import QuotaCore

enum MenuBarAppearance {
    static let warningBackground = NSColor(srgbRed: 0.60, green: 0.43, blue: 0, alpha: 1)
    static let criticalBackground = NSColor(srgbRed: 0.70, green: 0.10, blue: 0.08, alpha: 1)
    static let badgeText = NSAttributedString.Key("CliProxyQuota.badgeText")
    static let badgeBackground = NSAttributedString.Key("CliProxyQuota.badgeBackground")
    private static var cachedImages: [String: NSImage] = [:]

    private static func image(text: String, severity: TrayQuotaSeverity) -> NSImage {
        let key = "\(severity):\(text)"
        if let image = cachedImages[key] { return image }
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
        let size = NSSize(width: ceil(label.size().width) + 12, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        (severity == .warning ? warningBackground : criticalBackground).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: 6, y: (size.height - label.size().height) / 2))
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = text
        cachedImages[key] = image
        return image
    }
    static func title(for readout: MenuBarReadout, mode: PercentageMode, window: MenuBarWindow,
                      includeSource: Bool = false, coloredWarnings: Bool = true, showResetCountdown: Bool = true) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let separator = coloredWarnings ? "  " : " · "
        let text = NSMutableAttributedString(string: " ", attributes: normal)
        if includeSource { text.append(NSAttributedString(string: readout.title + " ", attributes: normal)) }
        func append(_ remaining: Double?, label: String = "") {
            let value = label + (remaining.map { mode.formatted($0) } ?? "—")
            let severity = TrayQuotaSeverity.forRemaining(remaining)
            guard coloredWarnings && severity != .normal else {
                text.append(NSAttributedString(string: value, attributes: normal)); return
            }
            text.append(NSAttributedString(string: " ", attributes: normal))
            let attachment = NSTextAttachment()
            attachment.image = image(text: value, severity: severity)
            attachment.bounds = NSRect(x: 0, y: -4, width: attachment.image!.size.width, height: 18)
            let badge = NSMutableAttributedString(attachment: attachment)
            badge.addAttributes([badgeText: value, badgeBackground: severity == .warning ? warningBackground : criticalBackground],
                                range: NSRange(location: 0, length: badge.length))
            text.append(badge)
            text.append(NSAttributedString(string: " ", attributes: normal))
        }
        switch window {
        case .fiveHour: append(readout.fiveHour)
        case .weekly: append(readout.weekly)
        case .both:
            append(readout.fiveHour, label: "⁵ʰ ")
            text.append(NSAttributedString(string: separator, attributes: normal))
            append(readout.weekly, label: "ʷ ")
        }
        if showResetCountdown, let recovery = readout.recoveryText(window: window) {
            text.append(NSAttributedString(string: separator + recovery, attributes: normal))
        }
        return text
    }
}
