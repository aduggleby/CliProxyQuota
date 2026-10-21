import AppKit
import Foundation

@main struct MakeIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            // Explicit pixel dimensions avoid generating Retina-scaled iconset entries.
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let transform = NSAffineTransform()
            transform.scale(by: CGFloat(size) / 1024)
            transform.concat()
            let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 215, yRadius: 215)
            NSGradient(starting: NSColor(red: 0.11, green: 0.26, blue: 0.24, alpha: 1),
                ending: NSColor(red: 0.19, green: 0.43, blue: 0.36, alpha: 1))!.draw(in: background, angle: 60)
            QuotaBotIcon.draw(in: NSRect(x: 212, y: 182, width: 600, height: 600),
                color: NSColor(calibratedWhite: 0.94, alpha: 1),
                barsColor: NSColor(red: 0.65, green: 0.88, blue: 0.74, alpha: 1))
            NSGraphicsContext.restoreGraphicsState()
            let data = bitmap.representation(using: .png, properties: [:])!
            let names: [String]
            switch size {
            case 16: names = ["icon_16x16.png"]
            case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
            case 64: names = ["icon_32x32@2x.png"]
            case 128: names = ["icon_128x128.png"]
            case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
            case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
            default: names = ["icon_512x512@2x.png"]
            }
            for name in names { try data.write(to: output.appendingPathComponent(name)) }
        }
    }
}
