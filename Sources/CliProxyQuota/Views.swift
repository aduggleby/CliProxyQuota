import SwiftUI
import QuotaCore
import ServiceManagement

private let quotaGreen = Color(red: 0.26, green: 0.53, blue: 0.46)

struct QuotaPopover: View {
    @ObservedObject var store: QuotaStore
    @State private var expanded = Set<String>()
    @State private var listHeight: CGFloat = 440
    @State private var chromeHeight: CGFloat = 270
    private var listViewportHeight: CGFloat {
        min(listHeight, max(1, store.maximumPopoverHeight - chromeHeight))
    }
    init(store: QuotaStore, expandedInitially: Set<String> = []) {
        self.store = store; _expanded = State(initialValue: expandedInitially)
    }
    var body: some View {
        let occupiedListHeight = (!store.showSettings && !store.quotas.isEmpty) ? listViewportHeight : 0
        VStack(spacing: 0) {
            header
            Divider()
            if store.showSettings {
                ConnectionView(store: store)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("View", selection: $store.selectedView) {
                        Text("All accounts").tag("All accounts")
                        Text("Per account").tag("Per account")
                    }.pickerStyle(.segmented).labelsHidden()
                    if let issue = store.issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.quotas.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if store.selectedView == "All accounts" { overview } else { accountList }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if height > 0 && abs(listHeight - height) > 0.5 { listHeight = height }
                            }
                        }
                        .frame(height: listViewportHeight)
                        .scrollDisabled(listHeight <= listViewportHeight + 0.5)
                        if store.selectedView == "All accounts" {
                            Text("Averages of reporting accounts, grouped by matching quota. Different limits stay separate.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Show remaining percentage in menu bar", isOn: $store.showPercentage)
                            .font(.system(size: 11)).toggleStyle(.checkbox)
                        if store.isStale && !store.demo && store.lastUpdated != nil {
                            Label("Last known values · waiting for a successful refresh", systemImage: "clock.badge.exclamationmark")
                                .font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                }.padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(quotaGreen)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height - occupiedListHeight
        } action: { height in
            if !store.showSettings && !store.quotas.isEmpty && abs(chromeHeight - height) > 0.5 {
                chromeHeight = height
            }
        }
        .onChange(of: store.selectedView) { _, _ in store.onChange?() }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(quotaGreen)
                .frame(width: 34, height: 34).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("CliProxy Quota").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(store.demo ? "Demo · sample data" : store.lastUpdated == nil ? "Connect your instance" : store.issue != nil ? "Connection needs attention" : "\(store.quotas.count) accounts · \(host)")
                        .lineLimit(1).truncationMode(.middle)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { store.showSettings.toggle() } label: { Image(systemName: store.showSettings ? "xmark" : "slider.horizontal.3") }
                .buttonStyle(.plain).help(store.showSettings ? "Close settings" : "Connection settings")
                .accessibilityLabel(store.showSettings ? "Close settings" : "Connection settings")
        }.padding(20)
    }
    private var host: String { URL(string: store.endpoint)?.host ?? "CliProxy" }
    private var statusColor: Color { store.demo ? .secondary : store.issue != nil ? .orange : store.lastUpdated != nil ? quotaGreen : .secondary }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("REMAINING USAGE", "By quota pool")
            ForEach(Array(Set(store.pools.map(\.provider))).sorted(), id: \.self) { provider in
                let pools = store.pools.filter { $0.provider == provider }
                if let pool = pools.first {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider).font(.system(size: 13, weight: .semibold))
                                Text("\(pool.label) · \(pool.reportingAccounts)/\(pool.totalAccounts) reporting")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            percentage(pool.remaining)
                            pinButton(pool.id, label: "Pin \(provider) \(pool.label) to menu bar")
                        }
                        QuotaMeter(remaining: pool.remaining)
                        Text(QuotaWindow(id: "", label: "", remaining: 0, resetsAt: pool.nextReset).resetLabel())
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach(Array(pools.dropFirst())) { extra in
                            HStack(spacing: 5) {
                                Text(extra.label).lineLimit(1)
                                Text("· \(Int(extra.remaining.rounded()))% left").monospacedDigit()
                                Spacer(minLength: 0)
                                Text("\(extra.reportingAccounts)/\(extra.totalAccounts)").foregroundStyle(.tertiary)
                                pinButton(extra.id, label: "Pin \(provider) \(extra.label) to menu bar")
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 13)
                    Divider()
                }
            }
            if store.hasFailures {
                Button { store.selectedView = "Per account" } label: {
                    Label("Some accounts could not report quota", systemImage: "exclamationmark.triangle")
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 12)
            }
            if store.pools.isEmpty {
                Text("No supported quotas reported. Open Per account for details.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 16)
            }
        }
    }
    private var accountList: some View {
        VStack(spacing: 0) {
            sectionHeader("REMAINING BY ACCOUNT", "Expand for limits")
            ForEach(store.quotas) { q in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if expanded.contains(q.id) { expanded.remove(q.id) } else { expanded.insert(q.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(String(q.account.providerName.prefix(1))).font(.system(size: 12, weight: .semibold))
                                .frame(width: 29, height: 29).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(q.account.providerName).font(.system(size: 12, weight: .semibold))
                                Text(q.account.email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 3)
                            VStack(alignment: .trailing, spacing: 4) {
                                if let first = q.windows.first {
                                    Text("\(Int(first.remaining.rounded()))% left").font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(first.remaining <= 20 ? .orange : .primary)
                                    Text(first.label).font(.system(size: 11)).foregroundStyle(.secondary)
                                } else { Text(q.account.disabled ? "Disabled" : "Unavailable").font(.system(size: 11)).foregroundStyle(.secondary) }
                            }
                            Image(systemName: expanded.contains(q.id) ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle()).padding(.vertical, 13)
                    }.buttonStyle(.plain).accessibilityLabel("\(q.account.providerName), \(q.account.email), expand quota limits")
                    if expanded.contains(q.id) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let issue = q.issue {
                                Text(issue).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(q.windows) { window in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(window.label).font(.system(size: 11))
                                        Spacer()
                                        Text("\(Int(window.remaining.rounded()))% remaining").font(.system(size: 11)).monospacedDigit()
                                        pinButton("\(q.id)|\(window.id)", label: "Pin \(window.label) for \(q.account.email)")
                                    }
                                    QuotaMeter(remaining: window.remaining)
                                    Text(window.resetLabel()).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.bottom, 14)
                    }
                }
                Divider()
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.refreshing ? "arrow.triangle.2.circlepath" : "battery.0percent")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(store.refreshing ? "Reading account quotas…" : store.lastUpdated != nil ? "No accounts found" : "Your quotas, at a glance")
                .font(.system(size: 14, weight: .medium))
            Text(store.lastUpdated != nil ? "Add OAuth accounts to your CliProxy instance to see their remaining limits." : "Connect to CliProxy to see remaining usage and reset times for each account.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !store.refreshing { Button("Connection settings") { store.showSettings = true }.buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity).padding(.vertical, 25)
    }
    private var footer: some View {
        HStack {
            if store.refreshing { ProgressView().controlSize(.mini); Text("Refreshing…") }
            else if store.demo { Text("Sample data · no connection") }
            else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { _ in Text("Updated \(updated, style: .relative) ago") }
            } else { Text("Not connected") }
            Spacer()
            Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(store.refreshing || store.demo).buttonStyle(.plain).keyboardShortcut("r")
            Menu {
                if let version = store.apiVersion { Text(version) }
                Button("Quit CliProxy Quota") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 21)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
    }
    private func sectionHeader(_ title: String, _ trailing: String) -> some View {
        HStack { Text(title); Spacer(); Text(trailing) }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
    }
    private func percentage(_ value: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(value.rounded()))").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("% left").font(.system(size: 11)).foregroundStyle(.secondary)
        }.foregroundStyle(value <= 20 ? Color.orange : Color.primary)
    }
    private func pinButton(_ id: String, label: String) -> some View {
        Button { store.pin = store.pin == id ? "" : id } label: {
            Image(systemName: store.pin == id ? "pin.fill" : "pin").font(.system(size: 10))
                .foregroundStyle(store.pin == id ? quotaGreen : Color.secondary.opacity(0.7))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct QuotaMeter: View {
    let remaining: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule().fill(remaining <= 20 ? Color.orange.opacity(0.85) : quotaGreen)
                    .frame(width: geometry.size.width * min(1, max(0, remaining / 100)))
            }
        }.frame(height: 6)
            .accessibilityLabel("\(Int(remaining.rounded())) percent remaining")
    }
}

struct ConnectionView: View {
    @ObservedObject var store: QuotaStore
    @State private var endpoint = ""
    @State private var key = ""
    @State private var allowInsecureHTTP = false
    @State private var interval = 120.0
    @State private var error: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Connection").font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Instance URL").font(.system(size: 12, weight: .medium))
                TextField("http://localhost:8317", text: $endpoint).textFieldStyle(.roundedBorder)
                Text("HTTPS is recommended. HTTP sends the management key unencrypted.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Toggle("Allow HTTP for this instance", isOn: $allowInsecureHTTP).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 6) {
                Text("Management key").font(.system(size: 12, weight: .medium))
                SecureField("CliProxy management key", text: $key).textFieldStyle(.roundedBorder)
                Text("Stored in macOS Keychain for this instance. Provider tokens stay on your proxy.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Refresh every", selection: $interval) {
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
                Text("10 minutes").tag(600.0)
            }.font(.system(size: 12))
            Toggle("Open at login", isOn: $launchAtLogin).font(.system(size: 12))
                .disabled(store.demo)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { self.error = "Login item could not be updated. Check System Settings → General → Login Items." }
                }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Quota access only").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Save & connect") {
                    do {
                        let base = try InstanceURL.normalized(endpoint, allowInsecureHTTP: allowInsecureHTTP)
                        let effectiveKey = key.isEmpty ? try Keychain.read(for: base.absoluteString) : key
                        try store.configure(endpoint: endpoint, key: effectiveKey, interval: interval, allowInsecureHTTP: allowInsecureHTTP)
                        key = ""
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(store.demo)
            }
        }.padding(20)
        .onAppear { endpoint = store.endpoint; interval = store.interval; allowInsecureHTTP = UserDefaults.standard.string(forKey: "insecureEndpoint") == store.endpoint }
    }
}
