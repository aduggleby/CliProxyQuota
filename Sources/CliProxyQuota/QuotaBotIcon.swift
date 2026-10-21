import AppKit

/// Shared vector artwork for the menu bar, popover, and application icon.
enum QuotaBotIcon {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func draw(in rect: NSRect, color: NSColor, barsColor: NSColor? = nil) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 24, yBy: rect.height / 24)
        transform.concat()
        color.setStroke()
        color.setFill()
        func line(_ start: NSPoint, _ end: NSPoint, width: CGFloat = 1.6) {
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: end)
            path.stroke()
        }
        let head = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 18, height: 15), xRadius: 5, yRadius: 5)
        head.lineWidth = 1.6
        head.stroke()
        line(NSPoint(x: 12, y: 19), NSPoint(x: 12, y: 22))
        NSBezierPath(ovalIn: NSRect(x: 10.7, y: 21.2, width: 2.6, height: 2.6)).fill()
        line(NSPoint(x: 1, y: 10), NSPoint(x: 1, y: 14), width: 2)
        line(NSPoint(x: 23, y: 10), NSPoint(x: 23, y: 14), width: 2)
        line(NSPoint(x: 9, y: 7), NSPoint(x: 15, y: 7), width: 1.2)
        (barsColor ?? color).setFill()
        for index in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: 6 + CGFloat(index) * 4.3, y: 10, width: 2.8, height: 4),
                xRadius: 0.6, yRadius: 0.6).fill()
        }
    }
}
