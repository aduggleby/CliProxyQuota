import Foundation
import CoreFoundation

public enum QuotaParser {
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        if let text = value as? String, let value = Double(text), value.isFinite { return value }
        return nil
    }
    static func text(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = number(value) { return String(format: "%.0f", value) }
        return nil
    }
    static func date(_ value: Any?) -> Date? {
        if let n = number(value) { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: value) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    public static func accounts(_ data: Data) throws -> [Account] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let entries = (json as? [String: Any])?["files"] as? [[String: Any]] ?? json as? [[String: Any]] else { throw QuotaError.malformed }
        var seen = Set<String>()
        return entries.compactMap { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let attributes = item["attributes"] as? [String: Any] ?? [:]
            let token = item["id_token"] as? [String: Any] ?? [:]
            let name = text(item["name"]) ?? text(item["id"]) ?? "Account"
            let index = text(item["auth_index"] ?? item["authIndex"]) ?? ""
            let provider = (text(item["provider"] ?? item["type"]) ?? "unknown").lowercased()
            let id = "\(provider):\(index.isEmpty ? name : index)"
            guard seen.insert(id).inserted else { return nil }
            let accountID = text(item["account_id"] ?? item["chatgpt_account_id"] ?? token["chatgpt_account_id"] ?? metadata["account_id"] ?? attributes["account_id"])
            return Account(id: id, authIndex: index, provider: provider, name: name,
                email: text(item["email"]) ?? text(metadata["email"]) ?? name,
                disabled: item["disabled"] as? Bool ?? false, accountID: accountID,
                projectID: text(item["project_id"] ?? metadata["project_id"] ?? attributes["project_id"] ?? attributes["gemini_virtual_project"]))
        }
    }
    public static func windows(provider: String, data: Data, now: Date = Date()) throws -> [QuotaWindow] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.malformed }
        var result: [QuotaWindow] = []
        switch provider {
        case "codex":
            func addLimit(_ limit: [String: Any], prefix: String = "", name: String = "") {
                for (key, fallback) in [("primary_window", "5-hour"), ("secondary_window", "Weekly")] {
                    let camel = key == "primary_window" ? "primaryWindow" : "secondaryWindow"
                    guard let w = (limit[key] ?? limit[camel]) as? [String: Any],
                          let used = number(w["used_percent"] ?? w["usedPercent"]) else { continue }
                    let duration = number(w["limit_window_seconds"] ?? w["limitWindowSeconds"])
                    let label: String
                    switch duration {
                    case 18000: label = "5-hour"
                    case 604800: label = "Weekly"
                    case let n? where n >= 2419200 && n <= 2678400: label = "Monthly"
                    case let n?: label = "\(Int(n / 3600))h window"
                    default: label = fallback
                    }
                    let reset = date(w["reset_at"] ?? w["resetAt"]) ?? number(w["reset_after_seconds"] ?? w["resetAfterSeconds"]).map { now.addingTimeInterval($0) }
                    result.append(QuotaWindow(id: prefix + label, label: name + label, remaining: 100 - used, resetsAt: reset, duration: duration))
                }
            }
            if let limit = (json["rate_limit"] ?? json["rateLimit"]) as? [String: Any] { addLimit(limit) }
            if let review = (json["code_review_rate_limit"] ?? json["codeReviewRateLimit"]) as? [String: Any] { addLimit(review, prefix: "review-", name: "Code review · ") }
            for item in (json["additional_rate_limits"] ?? json["additionalRateLimits"]) as? [[String: Any]] ?? [] {
                if let limit = (item["rate_limit"] ?? item["rateLimit"]) as? [String: Any] {
                    let name = text(item["limit_name"] ?? item["limitName"] ?? item["metered_feature"]) ?? "Additional"
                    addLimit(limit, prefix: "\(name)-", name: "\(name) · ")
                }
            }
        case "claude":
            let keys = [("five_hour", "5-hour"), ("seven_day", "Weekly"), ("seven_day_opus", "Weekly · Opus"), ("seven_day_sonnet", "Weekly · Sonnet"), ("seven_day_oauth_apps", "Weekly · OAuth apps"), ("seven_day_cowork", "Weekly · Cowork")]
            for (key, label) in keys {
                guard let w = json[key] as? [String: Any], let used = number(w["utilization"]) else { continue }
                result.append(QuotaWindow(id: key, label: label, remaining: 100 - used, resetsAt: date(w["resets_at"])))
            }
        case "gemini", "gemini-cli":
            for bucket in json["buckets"] as? [[String: Any]] ?? [] {
                guard let fraction = number(bucket["remainingFraction"]), let model = text(bucket["modelId"]) else { continue }
                let kind = text(bucket["tokenType"]) ?? "QUOTA"
                result.append(QuotaWindow(id: "\(model)-\(kind)", label: model + (kind == "REQUESTS" ? "" : " · \(kind.lowercased())"), remaining: fraction * 100, resetsAt: date(bucket["resetTime"])))
            }
        case "antigravity":
            // Older servers return fetchAvailableModels; newer ones use quota summary groups.
            for (groupIndex, group) in (json["groups"] as? [[String: Any]] ?? []).enumerated() {
                let name = text(group["displayName"] ?? group["display_name"]) ?? "Group \(groupIndex + 1)"
                for (bucketIndex, bucket) in (group["buckets"] as? [[String: Any]] ?? []).enumerated() {
                    guard let fraction = number(bucket["remainingFraction"] ?? bucket["remaining_fraction"]) else { continue }
                    let window = text(bucket["window"]) ?? "Quota"
                    let id = text(bucket["bucketId"] ?? bucket["bucket_id"]) ?? "\(name)-\(window)-\(bucketIndex)"
                    result.append(QuotaWindow(id: id, label: "\(name) · \(window)", remaining: fraction * 100, resetsAt: date(bucket["resetTime"] ?? bucket["reset_time"])))
                }
            }
            if let models = json["models"] as? [String: [String: Any]] {
                for (id, model) in models.sorted(by: { $0.key < $1.key }) {
                    guard let quota = model["quotaInfo"] as? [String: Any], let fraction = number(quota["remainingFraction"]) else { continue }
                    result.append(QuotaWindow(id: id, label: text(model["displayName"]) ?? id, remaining: fraction * 100, resetsAt: date(quota["resetTime"])))
                }
            }
        default: throw QuotaError.unsupported
        }
        guard !result.isEmpty else { throw QuotaError.malformed }
        // Duplicate provider buckets must not double-weight the aggregate.
        var ids = Set<String>()
        return result.filter { ids.insert($0.id).inserted }
    }
}
