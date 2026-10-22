import Foundation

/// Names and artwork coverage follow CLIProxyAPI's upstream management UI.
/// Custom OpenAI-compatible providers are open-ended and retain the generic fallback.
public enum ProviderIdentity {
    private static let aliases: [String: String] = [
        "anthropic": "claude", "claude-code": "claude", "open-ai": "openai",
        "gemini-cli": "gemini", "google-gemini": "gemini",
        "anti-gravity": "antigravity", "grok": "xai", "x-ai": "xai", "x.ai": "xai",
        "muse": "meta", "meta-ai": "meta", "moonshot": "kimi", "moonshot-ai": "kimi",
        "ai-studio": "aistudio", "google-ai-studio": "aistudio",
        "vertex-ai": "vertex", "google-vertex-ai": "vertex",
        "i-flow": "iflow", "open-router": "openrouter", "deep-seek": "deepseek",
        "z-ai": "glm", "z.ai": "glm", "zhipu": "glm", "mini-max": "minimax"
    ]
    private static let names: [String: String] = [
        "openai": "OpenAI", "codex": "Codex", "claude": "Claude", "gemini": "Gemini",
        "antigravity": "Antigravity", "aistudio": "Google AI Studio", "vertex": "Vertex AI",
        "kimi": "Kimi", "xai": "xAI", "meta": "Meta", "devin": "Devin",
        "qwen": "Qwen", "iflow": "iFlow", "openrouter": "OpenRouter",
        "deepseek": "DeepSeek", "glm": "GLM", "minimax": "MiniMax"
    ]
    public static let iconProviderKeys = ["openai", "codex", "claude", "gemini", "antigravity", "aistudio", "vertex", "kimi", "xai", "meta", "devin", "qwen", "iflow", "openrouter", "deepseek", "glm", "minimax"]
    public static func canonicalKey(_ provider: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        return aliases[key] ?? key
    }
    public static func displayName(_ provider: String) -> String {
        names[canonicalKey(provider)] ?? provider.capitalized
    }
    public static func assetName(for provider: String, dark: Bool) -> String? {
        switch canonicalKey(provider) {
        case "openai": return "openai"
        case "codex": return "codex"
        case "claude": return "claude"
        case "gemini", "aistudio": return "gemini"
        case "xai": return dark ? "grok-dark" : "grok"
        case "devin": return dark ? "devin-dark" : "devin"
        // Upstream names Kimi assets by their ink color rather than the background theme.
        case "kimi": return dark ? "kimi-light" : "kimi-dark"
        case let key where names[key] != nil: return key
        default: return nil
        }
    }
}
