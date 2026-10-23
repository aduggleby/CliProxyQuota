import Foundation
import CryptoKit
import QuotaCore

/// Persist only hashes, summed percentages, reset dates, and sample timestamps.
enum ProviderForecast {
    static func digest(_ components: [String]) -> String {
        let data = (try? JSONEncoder().encode(components)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func observations(for provider: String, quotas: [AccountQuota], endpoint: String) -> [ForecastObservation]? {
        let accounts = quotas.filter { !$0.account.disabled && $0.account.providerName == provider }
        guard !accounts.isEmpty, accounts.allSatisfy({ $0.issue == nil && !$0.windows.isEmpty }) else { return nil }
        let grouped = Dictionary(grouping: accounts.flatMap { account in
            account.windows.map { (account.account.id, $0) }
        }, by: { $0.1.id })
        return grouped.map { window, items in
            ForecastObservation(key: digest([endpoint, provider, window]),
                cohort: digest(items.map { $0.0 }.sorted()),
                remaining: items.reduce(0) { $0 + $1.1.remaining },
                reset: items.allSatisfy { $0.1.resetsAt != nil } ? items.compactMap { $0.1.resetsAt }.min() : nil,
                cycleResets: items.sorted { $0.0 < $1.0 }.compactMap { $0.1.resetsAt })
        }
    }
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CliProxy Quota", isDirectory: true).appendingPathComponent("forecast-history.json")
    }
    static func load() -> ForecastHistory {
        guard let data = try? Data(contentsOf: fileURL), data.count < 20_000_000,
              let history = try? JSONDecoder().decode(ForecastHistory.self, from: data) else { return ForecastHistory() }
        return history
    }
    static func save(_ history: ForecastHistory) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(history).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { /* Forecasts remain available in memory if local storage is unavailable. */ }
    }
    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
