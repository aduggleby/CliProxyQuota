import SwiftUI
import QuotaCore

@MainActor final class QuotaStore: ObservableObject {
    @Published var quotas: [AccountQuota] = []
    @Published var refreshing = false
    @Published var issue: String?
    @Published var lastUpdated: Date?
    @Published var apiVersion: String?
    @Published var showSettings = false
    @Published var settingsTab = "General"
    @Published var forecastEnabled: Bool { didSet {
        guard !demo else { return }
        UserDefaults.standard.set(forecastEnabled, forKey: "forecastEnabled")
        if forecastEnabled {
            if !isStale, let lastUpdated { recordForecast(at: lastUpdated) }
        } else { forecastHistory = ForecastHistory(); ProviderForecast.clear() }
    } }
    @Published var forecastLookback: ForecastLookback { didSet {
        if !demo { UserDefaults.standard.set(forecastLookback.rawValue, forKey: "forecastLookback") }
    } }
    @Published private var forecastHistory = ForecastHistory()
    private var forecastMaximumGap: TimeInterval { max(300, interval * 2.5) }
    func forecast(for provider: String, now: Date = Date()) -> UsageForecast {
        guard !isStale, let observations = ProviderForecast.observations(for: provider, quotas: quotas, endpoint: endpoint) else { return .unavailable }
        return forecastHistory.forecast(observations, lookback: forecastLookback, now: now, maximumGap: forecastMaximumGap)
    }
    private func recordForecast(at date: Date) {
        guard forecastEnabled else { return }
        let observations = Set(quotas.map { $0.account.providerName }).flatMap {
            ProviderForecast.observations(for: $0, quotas: quotas, endpoint: endpoint) ?? []
        }
        forecastHistory.record(observations, at: date, maximumGap: forecastMaximumGap)
        if !demo { ProviderForecast.save(forecastHistory) }
    }
    private func seedDemoForecasts(at now: Date) {
        let providers = Set(quotas.map { $0.account.providerName })
        for minutesAgo in stride(from: 120, through: 0, by: -2) {
            let observations = providers.flatMap { provider in
                (ProviderForecast.observations(for: provider, quotas: quotas, endpoint: endpoint) ?? []).map { observation in
                    let isCodexShort = provider == "Codex" && observation.key == ProviderForecast.digest([endpoint, provider, "5-hour"])
                    let extra = isCodexShort ? 90 * Double(min(40, minutesAgo)) / 60 : Double(minutesAgo) / 60
                    return ForecastObservation(key: observation.key, cohort: observation.cohort,
                        remaining: observation.remaining + extra, reset: observation.reset, cycleResets: observation.cycleResets)
                }
            }
            forecastHistory.record(observations, at: now.addingTimeInterval(-Double(minutesAgo) * 60), maximumGap: 300)
        }
    }
    @Published var appearance: AppAppearance { didSet {
        if !demo {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nativeAppearance
        }
    } }
    @Published var selectedView = "All accounts"
    @Published var maximumPopoverHeight: CGFloat = (NSScreen.main?.visibleFrame.height ?? 800) - 24
    @Published var endpoint: String
    @Published var percentageMode: PercentageMode { didSet { persist(percentageMode.rawValue, key: "percentageMode"); onChange?() } }
    @Published var menuBarWindow: MenuBarWindow { didSet { persist(menuBarWindow.rawValue, key: "menuBarWindow"); onChange?() } }
    @Published var menuSourceIDs: [String]? { didSet {
        if !demo {
            if let menuSourceIDs { UserDefaults.standard.set(menuSourceIDs, forKey: "menuSources") }
            else { UserDefaults.standard.removeObject(forKey: "menuSources") }
        }
        onChange?()
    } }
    @Published var interval: Double { didSet { if !demo { UserDefaults.standard.set(interval, forKey: "interval") }; restartTimer() } }
    let demo: Bool
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    var pools: [QuotaPool] { QuotaPool.make(from: quotas) }
    var hasFailures: Bool { quotas.contains { $0.issue != nil && !$0.account.disabled } }
    var configured: Bool { UserDefaults.standard.bool(forKey: "configured") }
    var managementUIURL: URL? {
        let allowHTTP = UserDefaults.standard.string(forKey: "insecureEndpoint") == endpoint
        return (try? InstanceURL.normalized(endpoint, allowInsecureHTTP: allowHTTP))?
            .appendingPathComponent("management.html")
    }
    var isStale: Bool { issue != nil || (lastUpdated.map { Date().timeIntervalSince($0) > max(interval * 2, 180) } ?? true) }
    var sourceOptions: [MenuBarSource] { MenuBarSource.options(from: quotas) }
    var resolvedSourceIDs: [String] {
        menuSourceIDs ?? (sourceOptions.first { $0.id == "provider:codex" } ?? sourceOptions.first).map { [$0.id] } ?? []
    }
    var menuReadouts: [MenuBarReadout] {
        resolvedSourceIDs.map { id in
            sourceOptions.first { $0.id == id }?.readout(from: quotas, stale: isStale) ??
                MenuBarReadout(id: id, title: "Unavailable", detail: "Selected source is unavailable", fiveHour: nil, weekly: nil)
        }
    }
    func toggleSource(_ id: String) {
        var ids = resolvedSourceIDs
        if ids.contains(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
        menuSourceIDs = ids
    }
    private func persist(_ value: String, key: String) { if !demo { UserDefaults.standard.set(value, forKey: key) } }
    init(demo: Bool = false) {
        self.demo = demo
        let defaults = UserDefaults.standard
        forecastEnabled = demo ? true : defaults.object(forKey: "forecastEnabled") as? Bool ?? true
        forecastLookback = demo ? .sixty : ForecastLookback(rawValue: defaults.integer(forKey: "forecastLookback")) ?? .sixty
        appearance = demo ? .system : AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        endpoint = demo ? "https://proxy.example.com" : defaults.string(forKey: "endpoint") ?? "http://localhost:8317"
        percentageMode = demo ? .remaining : PercentageMode(rawValue: defaults.string(forKey: "percentageMode") ?? "") ?? .remaining
        menuBarWindow = demo ? .both : MenuBarWindow(rawValue: defaults.string(forKey: "menuBarWindow") ?? "") ?? .both
        if demo { menuSourceIDs = ["provider:codex"] }
        else if let ids = defaults.stringArray(forKey: "menuSources") { menuSourceIDs = ids }
        else if defaults.object(forKey: "showPercentage") as? Bool == false { menuSourceIDs = [] }
        else if let oldPin = defaults.string(forKey: "pin"), !oldPin.isEmpty {
            if let separator = oldPin.firstIndex(of: "|") { menuSourceIDs = ["account:" + oldPin[..<separator]] }
            else if let provider = oldPin.split(separator: "/").first { menuSourceIDs = ["provider:" + provider] }
            else { menuSourceIDs = nil }
        } else { menuSourceIDs = nil }
        interval = defaults.object(forKey: "interval") as? Double ?? 120
        if demo { quotas = Self.sample; lastUpdated = Date(); apiVersion = "Demo"; seedDemoForecasts(at: lastUpdated!) }
        else if forecastEnabled { forecastHistory = ProviderForecast.load() }
        if !demo { NSApp.appearance = appearance.nativeAppearance }
    }
    func start() {
        guard !demo else { return }
        if configured { refresh() } else { showSettings = true }
        restartTimer()
    }
    func restartTimer() {
        timer?.invalidate()
        guard !demo else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(30, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        guard !demo, !refreshing, configured else { return }
        refreshing = true
        let epoch = generation
        refreshTask = Task {
            defer { if epoch == generation { refreshing = false; onChange?() } }
            do {
                let base = try InstanceURL.normalized(endpoint, allowInsecureHTTP: UserDefaults.standard.string(forKey: "insecureEndpoint") == endpoint)
                let key = try Keychain.read(for: base.absoluteString)
                let client = ProxyClient(base: base, key: key)
                let (api, accounts) = try await client.accounts()
                var result: [AccountQuota] = []
                // Bound concurrency: large pools should not burst provider quota endpoints.
                await withTaskGroup(of: AccountQuota.self) { group in
                    var iterator = accounts.makeIterator()
                    for _ in 0..<4 { if let a = iterator.next() { group.addTask { await client.quota(for: a, api: api) } } }
                    for await quota in group {
                        result.append(quota)
                        if !Task.isCancelled, let a = iterator.next() { group.addTask { await client.quota(for: a, api: api) } }
                    }
                }
                guard !Task.isCancelled, epoch == generation else { return }
                quotas = result.sorted { ($0.account.providerName, $0.account.email) < ($1.account.providerName, $1.account.email) }
                apiVersion = api == .v8 ? "API v8" : "Legacy API"
                issue = nil; lastUpdated = Date()
                recordForecast(at: lastUpdated!)
            } catch {
                guard !Task.isCancelled, epoch == generation else { return }
                issue = ProxyClient.message(for: error)
            }
        }
    }
    func configure(endpoint text: String, key: String, interval newInterval: Double, allowInsecureHTTP: Bool) throws {
        guard !demo else { return }
        let base = try InstanceURL.normalized(text, allowInsecureHTTP: allowInsecureHTTP)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaError.missingKey }
        try Keychain.save(key, for: base.absoluteString)
        generation += 1; refreshTask?.cancel(); refreshing = false
        quotas = []; lastUpdated = nil; issue = nil
        if endpoint != base.absoluteString {
            menuSourceIDs = nil
            forecastHistory = ForecastHistory(); ProviderForecast.clear()
        }
        endpoint = base.absoluteString
        UserDefaults.standard.set(allowInsecureHTTP ? endpoint : "", forKey: "insecureEndpoint")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(true, forKey: "configured")
        interval = newInterval
        showSettings = false
        refresh()
    }
    static var sample: [AccountQuota] {
        let now = Date()
        func account(_ index: String, _ provider: String, _ email: String) -> Account {
            Account(id: index, authIndex: index, provider: provider, name: email, email: email)
        }
        return [
            AccountQuota(account: account("demo-codex-1", "codex", "alex@personal.example"), windows: [
                QuotaWindow(id: "5-hour", label: "5-hour", remaining: 32, resetsAt: now.addingTimeInterval(8280)),
                QuotaWindow(id: "Weekly", label: "Weekly", remaining: 92, resetsAt: now.addingTimeInterval(183600))]),
            AccountQuota(account: account("demo-codex-2", "codex", "automation@work.example"), windows: [
                QuotaWindow(id: "5-hour", label: "5-hour", remaining: 88, resetsAt: now.addingTimeInterval(13320)),
                QuotaWindow(id: "Weekly", label: "Weekly", remaining: 76, resetsAt: now.addingTimeInterval(356400))]),
            AccountQuota(account: account("demo-claude", "claude", "alex@work.example"), windows: [
                QuotaWindow(id: "five_hour", label: "5-hour", remaining: 18, resetsAt: now.addingTimeInterval(2880)),
                QuotaWindow(id: "seven_day", label: "Weekly", remaining: 61, resetsAt: now.addingTimeInterval(97200))]),
            AccountQuota(account: account("demo-gemini", "gemini", "alex@personal.example"), windows: [
                QuotaWindow(id: "gemini-pro", label: "Gemini Pro", remaining: 93, resetsAt: now.addingTimeInterval(51540))])]
    }
}
