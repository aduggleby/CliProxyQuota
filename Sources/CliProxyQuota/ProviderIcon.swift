import AppKit
import SwiftUI

/// Provider marks are bundled locally and rendered in their supplied colors.
enum ProviderArtwork {
    private static let resources: Bundle = {
        // SwiftPM's executable resource lookup differs from a packaged macOS app.
        if let url = Bundle.main.url(forResource: "CliProxyQuota_CliProxyQuota", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for asset in ["openai", "claude", "gemini"] {
            if let url = resources.url(forResource: asset, withExtension: "png", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url), image.isValid { result[asset] = image }
        }
        return result
    }()
    static func image(for provider: String) -> NSImage? {
        let asset: String
        switch provider.lowercased() {
        case "codex", "openai": asset = "openai"
        case "claude", "anthropic": asset = "claude"
        case "gemini", "gemini-cli": asset = "gemini"
        default: return nil
        }
        return images[asset]
    }
    static func menuImage(for provider: String) -> NSImage? {
        guard let image = image(for: provider)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    static func verifyAssets() throws {
        for provider in ["codex", "claude", "gemini"] where image(for: provider) == nil {
            throw NSError(domain: "ProviderArtwork", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing bundled icon for \(provider)"])
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let root = Bundle.main.resourceURL,
                  resources.bundleURL.path.hasPrefix(root.path + "/") else {
                throw NSError(domain: "ProviderArtwork", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "App is not loading its own bundled provider artwork"])
            }
        }
        print("Verified bundled OpenAI, Claude, and Gemini provider icons")
    }
}

struct ProviderIcon: View {
    let provider: String
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let image = ProviderArtwork.image(for: provider) {
                Image(nsImage: image).renderingMode(.original).resizable().scaledToFit()
                    .padding(size * 0.1)
            } else {
                Text(String(provider.prefix(1)).uppercased()).font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
