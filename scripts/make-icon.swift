import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 52, y: 52, width: 920, height: 920)
    let path = NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215)
    NSGradient(starting: NSColor(red: 0.11, green: 0.26, blue: 0.24, alpha: 1), ending: NSColor(red: 0.19, green: 0.43, blue: 0.36, alpha: 1))!.draw(in: path, angle: 60)
    let battery = NSBezierPath(roundedRect: NSRect(x: 222, y: 342, width: 550, height: 340), xRadius: 60, yRadius: 60)
    NSColor.white.withAlphaComponent(0.92).setStroke(); battery.lineWidth = 27; battery.stroke()
    NSColor.white.withAlphaComponent(0.5).setFill()
    NSBezierPath(roundedRect: NSRect(x: 794, y: 452, width: 33, height: 120), xRadius: 12, yRadius: 12).fill()
    NSColor(red: 0.65, green: 0.88, blue: 0.74, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 257, y: 377, width: 353, height: 270), xRadius: 28, yRadius: 28).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
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
