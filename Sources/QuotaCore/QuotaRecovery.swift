import Foundation

/// The first reported reset that increases usable allowance across the selected accounts.
/// A reset only helps when the other main window no longer blocks that account.
public enum QuotaRecovery {
    public static func nextIncrease(in quotas: [AccountQuota]) -> Date? {
        quotas.filter { !$0.account.disabled && $0.issue == nil }.compactMap { quota -> Date? in
            let windows = [MenuBarWindow.fiveHour, .weekly].compactMap { period in
                quota.windows.first { $0.standardPeriod == period }
            }
            guard let baseline = windows.map(\.remaining).min(), baseline < 100 else { return nil }
            var values = windows.map(\.remaining)
            let events = windows.enumerated().compactMap { index, window in
                window.resetsAt.map { (date: $0, index: index) }
            }.sorted { $0.date < $1.date }
            for event in events {
                values[event.index] = 100
                if let usable = values.min(), usable > baseline + 0.000001 { return event.date }
            }
            return nil
        }.min()
    }
}
