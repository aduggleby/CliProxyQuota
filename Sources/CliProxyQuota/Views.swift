import SwiftUI
import QuotaCore
import ServiceManagement

private let quotaGreen = Color(red: 0.26, green: 0.53, blue: 0.46)

struct QuotaPopover: View {
    @ObservedObject var store: QuotaStore
    @State private var contentHeight: CGFloat = 440
    @State private var chromeHeight: CGFloat = 116
    private var viewportHeight: CGFloat { min(contentHeight, max(1, store.maximumPopoverHeight - chromeHeight)) }
    init(store: QuotaStore, expandedInitially: Set<String> = []) { self.store = store }
    var body: some View {
        let occupiedHeight = viewportHeight
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    if store.showSettings { SettingsView(store: store) }
                    else { quotaContent }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height > 0 && abs(contentHeight - height) > 0.5 { contentHeight = height }
                }
            }
            .frame(height: viewportHeight)
            .scrollDisabled(contentHeight <= viewportHeight + 0.5)
            Divider()
            footer
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(quotaGreen)
        .onGeometryChange(for: CGFloat.self) { $0.size.height - occupiedHeight } action: { height in
            if abs(chromeHeight - height) > 0.5 { chromeHeight = height }
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: QuotaBotIcon.menuBar).renderingMode(.template)
                .resizable().scaledToFit().frame(width: 23, height: 23).foregroundStyle(quotaGreen)
                .frame(width: 37, height: 37).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.showSettings ? "Settings" : "CliProxy Quota").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(store.issue != nil ? Color.orange : quotaGreen).frame(width: 5, height: 5)
                    Text(store.demo ? "Demo · sample data" : store.lastUpdated == nil ? "Connect your instance" : store.issue != nil ? "Connection needs attention" : "\(store.quotas.count) accounts · \(URL(string: store.endpoint)?.host ?? "CliProxy")")
                        .lineLimit(1).truncationMode(.middle)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { store.showSettings.toggle() } label: {
                Image(systemName: store.showSettings ? "arrow.left" : "slider.horizontal.3")
            }.buttonStyle(.plain)
                .help(store.showSettings ? "Back to quota views" : "Settings")
                .accessibilityLabel(store.showSettings ? "Back to quota views" : "Settings")
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }
    private var quotaContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("View", selection: $store.selectedView) {
                Text("All accounts").tag("All accounts")
                Text("Per account").tag("Per account")
            }.pickerStyle(.segmented).labelsHidden()
            if let issue = store.issue {
                Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if store.quotas.isEmpty { emptyState }
            else {
                HStack {
                    Text(store.percentageMode == .remaining ? "REMAINING USAGE" : "USAGE CONSUMED")
                    Spacer()
                    Text(store.selectedView == "All accounts" ? "Account averages" : "Individual accounts")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if store.selectedView == "All accounts" { overview } else { accountList }
                if store.selectedView == "All accounts" {
                    Text("Each provider is averaged separately. Reset times show the next account to reset.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if store.isStale && !store.demo && store.lastUpdated != nil {
                    Label("Last known values · waiting for a successful refresh", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Set(store.pools.map(\.provider))).sorted(), id: \.self) { provider in
                let pools = store.pools.filter { $0.provider == provider }
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(provider).font(.system(size: 13, weight: .semibold))
                        if let first = pools.first {
                            Text("\(first.reportingAccounts)/\(first.totalAccounts) reporting").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if pools.contains(where: { store.resolvedSourceIDs.contains("provider:" + $0.id.components(separatedBy: "/")[0]) }) { sourceBadge }
                    }
                    QuotaMetrics(windows: pools.map { QuotaWindow(id: $0.id, label: $0.label, remaining: $0.remaining, resetsAt: $0.nextReset) }, mode: store.percentageMode)
                }.padding(.vertical, 13)
                Divider()
            }
            if store.hasFailures {
                Button { store.selectedView = "Per account" } label: { Label("Some accounts could not report quota", systemImage: "exclamationmark.triangle") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 12)
            }
            if store.pools.isEmpty {
                Text("No supported quotas reported. Open Per account for details.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }
    }
    private var accountList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.quotas) { q in
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 9) {
                        Text(String(q.account.providerName.prefix(1))).font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(q.account.providerName).font(.system(size: 12, weight: .semibold))
                            Text(q.account.email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        if store.resolvedSourceIDs.contains("account:\(q.id)") { sourceBadge }
                    }
                    if let issue = q.issue {
                        Text(issue).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    QuotaMetrics(windows: q.windows, mode: store.percentageMode)
                }.padding(.vertical, 13)
                Divider()
            }
        }
    }
    private var sourceBadge: some View {
        Text("In menu bar").font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: QuotaBotIcon.menuBar).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 34, height: 34).foregroundStyle(.secondary)
            Text(store.refreshing ? "Reading account quotas…" : store.lastUpdated != nil ? "No accounts found" : "Your quotas, at a glance")
                .font(.system(size: 14, weight: .medium))
            Text("Connect to CliProxy to see account usage limits and reset times.").font(.system(size: 12)).foregroundStyle(.secondary)
            if !store.refreshing { Button("Settings") { store.showSettings = true }.buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 25)
    }
    private var footer: some View {
        HStack {
            if store.showSettings { Text("Display changes apply immediately") }
            else if store.refreshing { ProgressView().controlSize(.mini); Text("Refreshing…") }
            else if store.demo { Text("Sample data · no connection") }
            else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { _ in Text("Updated \(updated, style: .relative) ago") }
            } else { Text("Not connected") }
            Spacer()
            if !store.showSettings {
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing || store.demo).buttonStyle(.plain).keyboardShortcut("r")
            }
            if let managementURL = store.managementUIURL {
                Link(destination: managementURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open Management UI")
                .accessibilityLabel("Open Management UI")
                .disabled(store.demo)
            }
            Menu {
                if let version = store.apiVersion { Text(version) }
                Button("Quit CliProxy Quota") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 21)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct QuotaMetrics: View {
    let windows: [QuotaWindow]
    let mode: PercentageMode
    var body: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 13) {
            ForEach(Array(stride(from: 0, to: windows.count, by: 2)), id: \.self) { index in
                GridRow(alignment: .top) {
                    metric(windows[index])
                    if index + 1 < windows.count { metric(windows[index + 1]) }
                    else { Color.clear.frame(height: 1).gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.label).font(.system(size: 11)).lineLimit(2)
                Spacer(minLength: 0)
                Text(mode.formatted(window.remaining)).font(.system(size: 19, weight: .medium)).monospacedDigit()
                    .foregroundStyle(window.remaining <= 20 ? Color.orange : Color.primary)
            }
            QuotaMeter(remaining: window.remaining, mode: mode)
            Text(window.resetLabel()).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuotaMeter: View {
    let remaining: Double
    var mode: PercentageMode = .remaining
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule().fill(remaining <= 20 ? Color.orange.opacity(0.85) : quotaGreen)
                    .frame(width: geometry.size.width * min(1, max(0, mode.value(for: remaining) / 100)))
            }
        }.frame(height: 5)
            .accessibilityLabel("\(mode.formatted(remaining)) \(mode.suffix)")
    }
}

struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @State private var endpoint = ""
    @State private var key = ""
    @State private var allowInsecureHTTP = false
    @State private var error: String?
    @State private var connectionStatus = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var sourceSummary: String {
        let ids = store.resolvedSourceIDs
        if ids.isEmpty { return "Icon only · no sources" }
        if ids.count > 1 { return "\(ids.count) sources selected" }
        guard let source = store.sourceOptions.first(where: { $0.id == ids.first }) else { return "Selected source unavailable" }
        return "\(source.title) · \(source.isProvider ? "all accounts" : source.detail)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Display")
            HStack {
                Text("Percentages")
                Spacer()
                SettingsSegments(values: PercentageMode.allCases, title: { $0.title }, selection: $store.percentageMode)
                    .frame(width: 216).accessibilityLabel("Percentages")
            }.font(.system(size: 12, weight: .medium))
            HStack {
                Text("Menu bar display")
                Spacer()
                SettingsSegments(values: MenuBarWindow.allCases, title: { $0.title }, selection: $store.menuBarWindow)
                    .frame(width: 216).accessibilityLabel("Menu bar display")
            }.font(.system(size: 12, weight: .medium))
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Source").font(.system(size: 12, weight: .medium))
                SourceMenuButton(summary: sourceSummary, sources: store.sourceOptions,
                    selectedIDs: store.resolvedSourceIDs, onToggle: store.toggleSource)
                    .frame(maxWidth: .infinity)
                Text("Select one or more sources. Each gets its own menu bar item; provider averages stay separate.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 3)
            heading("Connection")
            VStack(alignment: .leading, spacing: 7) {
                Text("Instance URL").font(.system(size: 12, weight: .medium))
                TextField("http://localhost:8317", text: $endpoint).textFieldStyle(.roundedBorder)
                Toggle("Allow HTTP for this instance", isOn: $allowInsecureHTTP).font(.system(size: 11)).toggleStyle(.checkbox)
                Text("HTTP sends the management password unencrypted.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Management password").font(.system(size: 12, weight: .medium))
                SecureField(store.configured && !store.demo ? "Saved in Keychain · leave blank to keep" : "CliProxy management password", text: $key)
                    .textFieldStyle(.roundedBorder)
                Text("Stored securely in macOS Keychain for this instance.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text(connectionStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Save & connect", action: saveConnection).buttonStyle(.bordered).disabled(store.demo)
            }
            Divider().padding(.vertical, 3)
            heading("General")
            HStack {
                Text("Refresh every")
                Spacer()
                Picker("Refresh every", selection: $store.interval) {
                    Text("1 minute").tag(60.0); Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0); Text("10 minutes").tag(600.0)
                }.labelsHidden().frame(width: 216)
            }.font(.system(size: 12))
            Toggle("Open at login", isOn: $launchAtLogin).font(.system(size: 12)).disabled(store.demo)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { self.error = "Login item could not be updated. Check System Settings → General → Login Items." }
                }
            Divider()
            HStack { Spacer(); Button("Done") { key = ""; store.showSettings = false }.buttonStyle(.borderedProminent) }
        }
        .onAppear {
            endpoint = store.endpoint
            allowInsecureHTTP = !store.demo && UserDefaults.standard.string(forKey: "insecureEndpoint") == store.endpoint
        }
    }
    private func heading(_ text: String) -> some View { Text(text).font(.system(size: 16, weight: .semibold)) }
    private func saveConnection() {
        do {
            let base = try InstanceURL.normalized(endpoint, allowInsecureHTTP: allowInsecureHTTP)
            let effectiveKey = key.isEmpty ? try Keychain.read(for: base.absoluteString) : key
            try store.configure(endpoint: endpoint, key: effectiveKey, interval: store.interval, allowInsecureHTTP: allowInsecureHTTP)
            key = ""; error = nil; connectionStatus = "Connecting…"
        } catch { self.error = error.localizedDescription }
    }
}
