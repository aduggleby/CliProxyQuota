import AppKit
import SwiftUI
import QuotaCore

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
        let assets = Set(ProviderIdentity.iconProviderKeys.flatMap { provider in
            [ProviderIdentity.assetName(for: provider, dark: false), ProviderIdentity.assetName(for: provider, dark: true)].compactMap { $0 }
        })
        for asset in assets {
            if let url = resources.url(forResource: asset, withExtension: "png", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url), image.isValid { result[asset] = image }
        }
        return result
    }()
    static func image(for provider: String, dark: Bool = false) -> NSImage? {
        guard let asset = ProviderIdentity.assetName(for: provider, dark: dark) else { return nil }
        return images[asset]
    }
    static func menuImage(for provider: String, dark: Bool = false) -> NSImage? {
        guard let image = image(for: provider, dark: dark)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    static func verifyAssets() throws {
        for provider in ProviderIdentity.iconProviderKeys {
            for dark in [false, true] {
                guard let image = image(for: provider, dark: dark),
                      image.representations.contains(where: { $0.pixelsWide >= 32 && $0.pixelsHigh >= 32 }) else {
                    throw NSError(domain: "ProviderArtwork", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing or undersized bundled icon for \(provider) (dark: \(dark))"])
                }
            }
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let root = Bundle.main.resourceURL,
                  resources.bundleURL.path.hasPrefix(root.path + "/") else {
                throw NSError(domain: "ProviderArtwork", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "App is not loading its own bundled provider artwork"])
            }
        }
        print("Verified bundled icons for all \(ProviderIdentity.iconProviderKeys.count) provider identities in both appearances")
    }
}

struct ProviderIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let provider: String
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let image = ProviderArtwork.image(for: provider, dark: colorScheme == .dark) {
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
