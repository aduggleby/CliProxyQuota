import Foundation

public struct QuotaWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let remaining: Double
    public let resetsAt: Date?
    public let duration: TimeInterval?
    public init(id: String, label: String, remaining: Double, resetsAt: Date? = nil, duration: TimeInterval? = nil) {
        self.id = id; self.label = label
        self.remaining = min(100, max(0, remaining))
        self.resetsAt = resetsAt; self.duration = duration
    }
    public func resetLabel(now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "Reset due · refresh to check" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
}

public struct Account: Identifiable, Equatable, Sendable {
    public let id: String
    public let authIndex: String
    public let provider: String
    public let name: String
    public let email: String
    public let disabled: Bool
    public let accountID: String?
    public let projectID: String?
    public init(id: String, authIndex: String, provider: String, name: String, email: String, disabled: Bool = false, accountID: String? = nil, projectID: String? = nil) {
        self.id = id; self.authIndex = authIndex; self.provider = provider
        self.name = name; self.email = email; self.disabled = disabled
        self.accountID = accountID; self.projectID = projectID
    }
    public var providerName: String { ProviderIdentity.displayName(provider) }

}

public struct AccountQuota: Identifiable, Equatable, Sendable {
    public var id: String { account.id }
    public let account: Account
    public var windows: [QuotaWindow]
    public var issue: String?
    public init(account: Account, windows: [QuotaWindow] = [], issue: String? = nil) {
        self.account = account; self.windows = windows; self.issue = issue
    }
}

public struct QuotaPool: Identifiable, Sendable {
    public let id: String
    public let provider: String
    public let label: String
    public let remaining: Double
    public let nextReset: Date?
    public let reportingAccounts: Int
    public let totalAccounts: Int
    public static func make(from accounts: [AccountQuota]) -> [QuotaPool] {
        let active = accounts.filter { !$0.account.disabled }
        let grouped = Dictionary(grouping: active.flatMap { q in
            q.windows.map { (q.account.provider, q.account.providerName, $0) }
        }, by: { "\($0.0)/\($0.2.id)" })
        return grouped.map { key, items in
            let first = items[0]
            return QuotaPool(id: key, provider: first.1, label: first.2.label,
                remaining: items.reduce(0) { $0 + $1.2.remaining } / Double(items.count),
                nextReset: items.compactMap { $0.2.resetsAt }.min(),
                reportingAccounts: items.count,
                totalAccounts: active.filter { $0.account.provider == first.0 }.count)
        }.sorted { a, b in
            if a.provider != b.provider { return a.provider < b.provider }
            func priority(_ label: String) -> Int { label == "5-hour" ? 0 : label == "Weekly" ? 1 : 2 }
            if priority(a.label) != priority(b.label) { return priority(a.label) < priority(b.label) }
            return a.label < b.label
        }
    }
}

public enum QuotaError: LocalizedError {
    case invalidURL, missingKey, http(Int), providerHTTP(Int), malformed, missingIndex, missingProject, unsupported
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use HTTPS, or explicitly allow HTTP for this instance. Remove credentials, query strings, and fragments."
        case .missingKey: return "Enter your CliProxy management key in Settings."
        case .http(401): return "Management key rejected. Check the key in Settings."
        case .http(403): return "Management access denied. Check remote-management access on your server."
        case .http(404): return "Management API not found. Check the instance URL and whether management is enabled."
        case .http(let code): return "CliProxy returned HTTP \(code)."
        case .providerHTTP(let code): return "Provider returned HTTP \(code). Quota could not be read."
        case .malformed: return "The API returned an unrecognized quota response."
        case .missingIndex: return "No auth_index was returned for this account."
        case .missingProject: return "No Google project ID was returned for this account."
        case .unsupported: return "This provider does not have a supported quota reader yet."
        }
    }
}

public enum InstanceURL {
    public static func normalized(_ text: String, allowInsecureHTTP: Bool = false) throws -> URL {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && (allowInsecureHTTP || ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)))
        else { throw QuotaError.invalidURL }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/v0/management", "/v8/management", "/management.html"] where path.hasSuffix(suffix) {
            path = String(path.dropLast(suffix.count)); break
        }
        parts.path = path
        guard let url = parts.url else { throw QuotaError.invalidURL }
        return url
    }
}
