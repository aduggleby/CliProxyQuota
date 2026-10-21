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
            let values = matching.compactMap { $0.windows.first { $0.standardPeriod == period }?.remaining }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return MenuBarReadout(id: id, title: isProvider ? title : "\(title) · \(detail)",
            detail: isProvider ? "\(title) · account average" : "\(title) · \(detail)",
            fiveHour: average(.fiveHour), weekly: average(.weekly))
    }
}

public struct MenuBarReadout: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let fiveHour: Double?
    public let weekly: Double?
    public init(id: String, title: String, detail: String, fiveHour: Double?, weekly: Double?) {
        self.id = id; self.title = title; self.detail = detail; self.fiveHour = fiveHour; self.weekly = weekly
    }
    public func text(mode: PercentageMode, window: MenuBarWindow, includeSource: Bool = false) -> String {
        func format(_ n: Double?) -> String { n.map { mode.formatted($0) } ?? "—" }
        let value: String
        switch window {
        case .fiveHour: value = format(fiveHour)
        case .weekly: value = format(weekly)
        case .both: value = "⁵ʰ \(format(fiveHour)) · ʷ \(format(weekly))"
        }
        return includeSource ? "\(title) \(value)" : value
    }
    public func tooltip(mode: PercentageMode, window: MenuBarWindow) -> String {
        func describe(_ n: Double?, _ label: String) -> String {
            n.map { "\(label): \(mode.formatted($0)) \(mode.suffix)" } ?? "\(label): unavailable"
        }
        let values = (window == .weekly ? [] : [describe(fiveHour, "5-hour")]) +
            (window == .fiveHour ? [] : [describe(weekly, "Weekly")])
        return ([detail] + values).joined(separator: " · ")
    }
}
