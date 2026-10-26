import Foundation

public enum PercentageMode: String, CaseIterable, Sendable {
    case remaining, used
    public var title: String { self == .remaining ? "Remaining" : "Used" }
    public var suffix: String { self == .remaining ? "remaining" : "used" }
    public func value(for remaining: Double) -> Double { self == .remaining ? remaining : 100 - remaining }
    public func formatted(_ remaining: Double) -> String { "\(Int(value(for: remaining).rounded()))%" }
}

public enum MenuBarWindow: String, CaseIterable, Sendable {
    case fiveHour, weekly, both
    public var title: String {
        switch self { case .fiveHour: return "5-hour"; case .weekly: return "Weekly"; case .both: return "Both" }
    }
}

extension QuotaWindow {
    /// Only the main subscription windows qualify; code-review/model-specific pools stay separate.
    public var standardPeriod: MenuBarWindow? {
        if label == "5-hour" { return .fiveHour }
        if label == "Weekly" { return .weekly }
        return nil
    }
}

public struct MenuBarSource: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let provider: String
    public let accountID: String?
    public var isProvider: Bool { accountID == nil }

    public static func options(from quotas: [AccountQuota]) -> [MenuBarSource] {
        let active = quotas.filter { !$0.account.disabled }
        let providers = Dictionary(grouping: active, by: { $0.account.provider }).map { key, items in
            MenuBarSource(id: "provider:\(key)", title: items[0].account.providerName,
                detail: "All \(items.count) account\(items.count == 1 ? "" : "s")", provider: key, accountID: nil)
        }.sorted { $0.title < $1.title }
        return providers + active.map { q in
            MenuBarSource(id: "account:\(q.id)", title: q.account.providerName, detail: q.account.email,
                provider: q.account.provider, accountID: q.id)
        }.sorted { ($0.title, $0.detail) < ($1.title, $1.detail) }
    }

    public func readout(from quotas: [AccountQuota], stale: Bool) -> MenuBarReadout {
        let matching = quotas.filter { !$0.account.disabled && (accountID == nil ? $0.account.provider == provider : $0.id == accountID) }
        func average(_ period: MenuBarWindow) -> Double? {
            guard !stale else { return nil }
            let values = matching.compactMap { quota -> Double? in
                guard quota.issue == nil,
                      let remaining = quota.windows.first(where: { $0.standardPeriod == period })?.remaining else { return nil }
                if period == .fiveHour, let weekly = quota.windows.first(where: { $0.standardPeriod == .weekly })?.remaining {
                    return min(remaining, weekly)
                }
                return remaining
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return MenuBarReadout(id: id, title: isProvider ? title : "\(title) · \(detail)",
            detail: isProvider ? "\(title) · account average" : "\(title) · \(detail)",
            fiveHour: average(.fiveHour), weekly: average(.weekly),
            fiveHourIsWeeklyCapped: !stale && matching.contains { quota in
                guard quota.issue == nil,
                      let five = quota.windows.first(where: { $0.standardPeriod == .fiveHour }),
                      let weekly = quota.windows.first(where: { $0.standardPeriod == .weekly }) else { return false }
                return weekly.remaining < five.remaining
            })
    }
}

public struct MenuBarReadout: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let fiveHour: Double?
    public let weekly: Double?
    public let fiveHourIsWeeklyCapped: Bool
    public init(id: String, title: String, detail: String, fiveHour: Double?, weekly: Double?, fiveHourIsWeeklyCapped: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.fiveHour = fiveHour; self.weekly = weekly
        self.fiveHourIsWeeklyCapped = fiveHourIsWeeklyCapped
    }
    public func text(mode: PercentageMode, window: MenuBarWindow, includeSource: Bool = false) -> String {
        parts(mode: mode, window: window, includeSource: includeSource).map(\.text).joined()
    }
    public func parts(mode: PercentageMode, window: MenuBarWindow, includeSource: Bool = false) -> [MenuBarTextPart] {
        func percentage(_ value: Double?) -> MenuBarTextPart {
            MenuBarTextPart(text: value.map { mode.formatted($0) } ?? "—", remaining: value)
        }
        var result: [MenuBarTextPart] = includeSource ? [.init(text: title + " ")] : []
        switch window {
        case .fiveHour: result.append(percentage(fiveHour))
        case .weekly: result.append(percentage(weekly))
        case .both:
            result += [.init(text: "⁵ʰ "), percentage(fiveHour), .init(text: " · ʷ "), percentage(weekly)]
        }
        return result
    }
    public func tooltip(mode: PercentageMode, window: MenuBarWindow) -> String {
        func describe(_ n: Double?, _ label: String) -> String {
            n.map { "\(label): \(mode.formatted($0)) \(mode.suffix)" } ?? "\(label): unavailable"
        }
        let values = (window == .weekly ? [] : [describe(fiveHour, fiveHourIsWeeklyCapped ? "5-hour (limited by weekly)" : "5-hour")]) +
            (window == .fiveHour ? [] : [describe(weekly, "Weekly")])
        return ([detail] + values).joined(separator: " · ")
    }
}

public enum TrayQuotaSeverity: Equatable, Sendable {
    case normal, warning, critical
    public static func forRemaining(_ value: Double?) -> Self {
        guard let value, value.isFinite else { return .normal }
        if value < 10 { return .critical }
        if value <= 25 { return .warning }
        return .normal
    }
}

public struct MenuBarTextPart: Equatable, Sendable {
    public let text: String
    public let remaining: Double?
    public var severity: TrayQuotaSeverity { TrayQuotaSeverity.forRemaining(remaining) }
    public init(text: String, remaining: Double? = nil) { self.text = text; self.remaining = remaining }
}
