import SwiftUI
import QuotaCore

@MainActor final class QuotaStore: ObservableObject {
    @Published var quotas: [AccountQuota] = []
    @Published var refreshing = false
    @Published var issue: String?
    @Published var lastUpdated: Date?
    @Published var apiVersion: String?
    @Published var showSettings = false
    @Published var selectedView = "All accounts"
    @Published var endpoint: String
    @Published var showPercentage: Bool { didSet { if !demo { UserDefaults.standard.set(showPercentage, forKey: "showPercentage") }; onChange?() } }
    @Published var pin: String { didSet { if !demo { UserDefaults.standard.set(pin, forKey: "pin") }; onChange?() } }
    @Published var interval: Double { didSet { if !demo { UserDefaults.standard.set(interval, forKey: "interval") }; restartTimer() } }
    let demo: Bool
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    var pools: [QuotaPool] { QuotaPool.make(from: quotas) }
    var hasFailures: Bool { quotas.contains { $0.issue != nil && !$0.account.disabled } }
    var configured: Bool { UserDefaults.standard.bool(forKey: "configured") }
    var isStale: Bool { issue != nil || (lastUpdated.map { Date().timeIntervalSince($0) > max(interval * 2, 180) } ?? true) }
    var menuValue: Double? {
        guard !isStale, !demo else { return nil }
        if !pin.isEmpty {
            for q in quotas {
                for w in q.windows where "\(q.id)|\(w.id)" == pin { return w.remaining }
            }
            return pools.first { $0.id == pin }?.remaining
        }
        return pools.first?.remaining
    }
    init(demo: Bool = false) {
        self.demo = demo
        let defaults = UserDefaults.standard
        endpoint = demo ? "https://proxy.example.com" : defaults.string(forKey: "endpoint") ?? "http://localhost:8317"
        showPercentage = defaults.object(forKey: "showPercentage") as? Bool ?? true
        pin = demo ? "" : defaults.string(forKey: "pin") ?? ""
        interval = defaults.object(forKey: "interval") as? Double ?? 120
        if demo { quotas = Self.sample; lastUpdated = Date(); apiVersion = "Demo" }
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
        quotas = []; lastUpdated = nil; issue = nil; pin = ""
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
                QuotaWindow(id: "5-hour", label: "5-hour", remaining: 86, resetsAt: now.addingTimeInterval(8280)),
                QuotaWindow(id: "Weekly", label: "Weekly", remaining: 92, resetsAt: now.addingTimeInterval(183600))]),
            AccountQuota(account: account("demo-codex-2", "codex", "automation@work.example"), windows: [
                QuotaWindow(id: "5-hour", label: "5-hour", remaining: 58, resetsAt: now.addingTimeInterval(13320)),
                QuotaWindow(id: "Weekly", label: "Weekly", remaining: 76, resetsAt: now.addingTimeInterval(356400))]),
            AccountQuota(account: account("demo-claude", "claude", "alex@work.example"), windows: [
                QuotaWindow(id: "five_hour", label: "5-hour", remaining: 18, resetsAt: now.addingTimeInterval(2880)),
                QuotaWindow(id: "seven_day", label: "Weekly", remaining: 61, resetsAt: now.addingTimeInterval(97200))]),
            AccountQuota(account: account("demo-gemini", "gemini", "alex@personal.example"), windows: [
                QuotaWindow(id: "gemini-pro", label: "Gemini Pro", remaining: 93, resetsAt: now.addingTimeInterval(51540))])]
    }
}
