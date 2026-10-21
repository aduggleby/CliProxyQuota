import Foundation

/// Never follow redirects carrying management credentials to another endpoint.
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct ProxyClient: Sendable {
    public enum API: String, Sendable { case v8, legacy }
    public let base: URL
    private let key: String
    private let session: URLSession
    public init(base: URL, key: String, session: URLSession? = nil) {
        self.base = base; self.key = key
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 35
            config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        }
    }
    private func request(_ path: String, body: Data? = nil) async throws -> Data {
        guard !key.isEmpty else { throw QuotaError.missingKey }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuotaError.malformed }
        guard (200..<300).contains(http.statusCode) else { throw QuotaError.http(http.statusCode) }
        guard data.count < 8_000_000 else { throw QuotaError.malformed }
        return data
    }
    public func accounts() async throws -> (API, [Account]) {
        do { return (.v8, try QuotaParser.accounts(await request("v8/management/credentials"))) }
        catch QuotaError.http(404) {
            return (.legacy, try QuotaParser.accounts(await request("v0/management/auth-files")))
        }
    }
    public func quota(for account: Account, api: API) async -> AccountQuota {
        if account.disabled { return AccountQuota(account: account, issue: "Disabled in CliProxy") }
        do {
            guard !account.authIndex.isEmpty else { throw QuotaError.missingIndex }
            var headers = ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json"]
            let url: String
            var method = "GET"
            var payload: String?
            switch account.provider {
            case "codex":
                url = "https://chatgpt.com/backend-api/wham/usage"
                headers["User-Agent"] = "codex-tui/0.149.1 (Mac OS; arm64)"
                if let id = account.accountID { headers["Chatgpt-Account-Id"] = id }
            case "claude":
                url = "https://api.anthropic.com/api/oauth/usage"
                headers["anthropic-beta"] = "oauth-2025-04-20"
                headers["User-Agent"] = "claude-cli/2.1.280 (external, cli)"
            case "gemini", "gemini-cli", "antigravity":
                guard let project = account.projectID else { throw QuotaError.missingProject }
                url = account.provider == "antigravity"
                    ? "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
                    : "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
                method = "POST"
                headers["User-Agent"] = account.provider == "antigravity" ? "antigravity/hub/2.23.0 darwin/arm64" : "GeminiCLI"
                let data = try JSONSerialization.data(withJSONObject: ["project": project])
                payload = String(decoding: data, as: UTF8.self)
            default: throw QuotaError.unsupported
            }
            var body: [String: Any] = ["auth_index": account.authIndex, "method": method, "url": url, "header": headers]
            if let payload { body["data"] = payload }
            let encoded = try JSONSerialization.data(withJSONObject: body)
            let response = try await request(api == .v8 ? "v8/management/requests/api-call" : "v0/management/api-call", body: encoded)
            let data = try Self.unwrap(response)
            return AccountQuota(account: account, windows: try QuotaParser.windows(provider: account.provider, data: data))
        } catch {
            // Do not display raw response bodies; they may contain credentials or account details.
            return AccountQuota(account: account, issue: Self.message(for: error))
        }
    }
    public static func unwrap(_ data: Data) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = QuotaParser.number(json["status_code"] ?? json["statusCode"]) else { throw QuotaError.malformed }
        guard (200..<300).contains(Int(code)) else { throw QuotaError.providerHTTP(Int(code)) }
        if let body = json["body"] as? String, let data = body.data(using: .utf8) { return data }
        if let body = json["body"], JSONSerialization.isValidJSONObject(body) { return try JSONSerialization.data(withJSONObject: body) }
        throw QuotaError.malformed
    }
    public static func message(for error: Error) -> String {
        if let error = error as? QuotaError { return error.localizedDescription }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled: return "Refresh cancelled."
            case .timedOut: return "Connection timed out. Try refreshing again."
            case .cannotConnectToHost, .cannotFindHost: return "Cannot reach CliProxy. Check the instance URL and server."
            case .notConnectedToInternet: return "You appear to be offline."
            default: return "Network connection failed (\(error.code.rawValue))."
            }
        }
        return "The API response could not be read."
    }
}
