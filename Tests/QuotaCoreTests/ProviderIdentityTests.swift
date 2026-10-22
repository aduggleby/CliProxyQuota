import XCTest
@testable import QuotaCore

final class ProviderIdentityTests: XCTestCase {
    func testEveryDisplayNameResolvesToItsArtwork() {
        XCTAssertEqual(Set(ProviderIdentity.iconProviderKeys).count, 17)
        for key in ProviderIdentity.iconProviderKeys {
            for dark in [false, true] {
                XCTAssertNotNil(ProviderIdentity.assetName(for: key, dark: dark))
                XCTAssertEqual(ProviderIdentity.assetName(for: ProviderIdentity.displayName(key), dark: dark),
                               ProviderIdentity.assetName(for: key, dark: dark), key)
            }
        }
    }
    func testAliasesAndUnknownProviders() {
        for (alias, canonical) in ["grok": "xai", "x.ai": "xai", "muse": "meta", "moonshot": "kimi", "google_ai_studio": "aistudio", "Vertex AI": "vertex", "Z.ai": "glm", " anti-gravity ": "antigravity"] {
            XCTAssertEqual(ProviderIdentity.canonicalKey(alias), canonical)
        }
        XCTAssertNil(ProviderIdentity.assetName(for: "my-custom-proxy", dark: false))
        XCTAssertEqual(ProviderIdentity.assetName(for: "kimi", dark: true), "kimi-light")
        XCTAssertEqual(ProviderIdentity.assetName(for: "xai", dark: true), "grok-dark")
    }
}
