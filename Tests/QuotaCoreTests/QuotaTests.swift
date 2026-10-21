import XCTest
@testable import QuotaCore

final class QuotaTests: XCTestCase {
    func data(_ text: String) -> Data { Data(text.utf8) }
    func testCodexRemainingAndWindowClassification() throws {
        let raw = data(#"{"rate_limit":{"primary_window":{"used_percent":16,"limit_window_seconds":604800,"reset_at":1900000000},"secondary_window":{"used_percent":28,"limit_window_seconds":18000,"reset_after_seconds":3600}},"code_review_rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":604800}}}"#)
        let now = Date(timeIntervalSince1970: 1800000000)
        let windows = try QuotaParser.windows(provider: "codex", data: raw, now: now)
        XCTAssertEqual(windows.map(\.label), ["Weekly", "5-hour", "Code review · Weekly"])
        XCTAssertEqual(windows.map(\.remaining), [84, 72, 90])
        XCTAssertEqual(windows[1].resetsAt, now.addingTimeInterval(3600))
    }
    func testCodexCamelCaseAndMonthly() throws {
        let windows = try QuotaParser.windows(provider: "codex", data: data(#"{"rateLimit":{"secondaryWindow":{"usedPercent":"44.5","limitWindowSeconds":2592000,"resetAt":1900000000000}}}"#))
        XCTAssertEqual(windows.first?.remaining, 55.5)
        XCTAssertEqual(windows.first?.label, "Monthly")
        XCTAssertEqual(windows.first?.resetsAt, Date(timeIntervalSince1970: 1900000000))
    }
    func testClaudeNullsAndResets() throws {
        let windows = try QuotaParser.windows(provider: "claude", data: data(#"{"five_hour":{"utilization":82,"resets_at":"2030-01-01T04:05:00.000Z"},"seven_day":{"utilization":39},"seven_day_opus":null}"#))
        XCTAssertEqual(windows.map(\.remaining), [18, 61])
        XCTAssertNotNil(windows[0].resetsAt); XCTAssertNil(windows[1].resetsAt)
    }
    func testGeminiFullQuotaWithoutRemainingAmount() throws {
        let windows = try QuotaParser.windows(provider: "gemini", data: data(#"{"buckets":[{"modelId":"gemini-pro","tokenType":"REQUESTS","remainingFraction":1,"resetTime":"2030-01-01T00:00:00Z"}]}"#))
        XCTAssertEqual(windows.first?.remaining, 100)
    }
    func testAntigravitySummary() throws {
        let windows = try QuotaParser.windows(provider: "antigravity", data: data(#"{"groups":[{"displayName":"Claude","buckets":[{"bucketId":"claude-weekly","window":"WEEKLY","remainingFraction":0.4,"resetTime":"2030-01-01T00:00:00Z"}]}]}"#))
        XCTAssertEqual(windows.first?.remaining, 40); XCTAssertEqual(windows.first?.id, "claude-weekly")
    }
    func testMissingOrBooleanPercentDoesNotBecomeFullQuota() {
        for used in ["null", "true", "\"not-a-number\""] {
            XCTAssertThrowsError(try QuotaParser.windows(provider: "codex", data: data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":\(used)}}}")))
        }
        XCTAssertThrowsError(try QuotaParser.windows(provider: "claude", data: data("{}")))
    }
    func testOutOfRangeIsClamped() throws {
        let windows = try QuotaParser.windows(provider: "claude", data: data(#"{"five_hour":{"utilization":120},"seven_day":{"utilization":-4}}"#))
        XCTAssertEqual(windows.map(\.remaining), [0, 100])
    }
    func testAccountsDeduplicateAndReadMetadata() throws {
        let accounts = try QuotaParser.accounts(data(#"{"files":[{"name":"test.json","auth_index":0,"provider":"codex","id_token":{"chatgpt_account_id":"workspace-id"}},{"name":"duplicate","auth_index":"0","provider":"codex"},{"name":"g","auth_index":"g","type":"gemini","metadata":{"project_id":"test-project"},"disabled":true}]}"#))
        XCTAssertEqual(accounts.count, 2); XCTAssertEqual(accounts[0].authIndex, "0")
        XCTAssertEqual(accounts[0].accountID, "workspace-id"); XCTAssertEqual(accounts[1].projectID, "test-project")
        XCTAssertTrue(accounts[1].disabled)
    }
    func testAggregateExcludesFailuresAndDisabledAndSeparatesProviders() {
        func q(_ id: String, _ provider: String, _ remaining: Double?, disabled: Bool = false) -> AccountQuota {
            AccountQuota(account: Account(id: id, authIndex: id, provider: provider, name: id, email: id, disabled: disabled), windows: remaining.map { [QuotaWindow(id: "5-hour", label: "5-hour", remaining: $0)] } ?? [], issue: remaining == nil ? "Unavailable" : nil)
        }
        let pools = QuotaPool.make(from: [q("a", "codex", 86), q("b", "codex", 58), q("c", "codex", nil), q("d", "codex", 0, disabled: true), q("e", "claude", 18)])
        XCTAssertEqual(pools.count, 2)
        let codex = pools.first { $0.provider == "Codex" }!
        XCTAssertEqual(codex.remaining, 72); XCTAssertEqual(codex.reportingAccounts, 2); XCTAssertEqual(codex.totalAccounts, 3)
    }
    func testUnwrapObjectAndStringBodies() throws {
        for input in [#"{"status_code":200,"body":"{\"ok\":true}"}"#, #"{"status_code":200,"body":{"ok":true}}"#] {
            let result = try ProxyClient.unwrap(data(input))
            XCTAssertEqual((try JSONSerialization.jsonObject(with: result) as? [String: Bool])?["ok"], true)
        }
        XCTAssertThrowsError(try ProxyClient.unwrap(data(#"{"status_code":429,"body":{"secret":"not-for-display"}}"#))) { error in
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }
    func testURLsRequireExplicitOptInForRemoteHTTP() throws {
        XCTAssertEqual(try InstanceURL.normalized("http://localhost:8317/v0/management/").absoluteString, "http://localhost:8317")
        XCTAssertEqual(try InstanceURL.normalized("https://proxy.example.com/prefix/v8/management").absoluteString, "https://proxy.example.com/prefix")
        XCTAssertThrowsError(try InstanceURL.normalized("http://proxy.example.com:8317/"))
        XCTAssertNoThrow(try InstanceURL.normalized("http://proxy.example.com:8317/", allowInsecureHTTP: true))
        for url in ["file:///etc/passwd", "https://user:password@example.com", "https://example.com?key=secret", "nonsense"] {
            XCTAssertThrowsError(try InstanceURL.normalized(url, allowInsecureHTTP: true))
        }
    }
    func testResetDueDoesNotInventFreshQuota() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(QuotaWindow(id: "x", label: "x", remaining: 0, resetsAt: now.addingTimeInterval(-1)).resetLabel(now: now), "Reset due · refresh to check")
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try XCTUnwrap(Self.handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class ProxyClientTests: XCTestCase {
    func makeClient(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> ProxyClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return ProxyClient(base: URL(string: "https://proxy.example.com")!, key: "synthetic-test-key", session: URLSession(configuration: config))
    }
    func testFallbackOn404() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            if request.url!.path == "/v8/management/credentials" { return (404, Data()) }
            XCTAssertEqual(request.url!.path, "/v0/management/auth-files")
            return (200, Data(#"{"files":[]}"#.utf8))
        }
        let (api, accounts) = try await client.accounts()
        XCTAssertEqual(api, .legacy); XCTAssertTrue(accounts.isEmpty)
    }
    func testUnauthorizedDoesNotRetry() async {
        var calls = 0
        let client = makeClient { _ in calls += 1; return (401, Data()) }
        do { _ = try await client.accounts(); XCTFail("Expected authorization failure") } catch {}
        XCTAssertEqual(calls, 1)
    }
    func testQuotaRequestUsesProxyAndPlaceholder() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url!.path, "/v8/management/requests/api-call")
            XCTAssertEqual(request.httpMethod, "POST")
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(buffer, count: n) }
                body = bytes
            }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
            XCTAssertEqual(json["auth_index"] as? String, "test-account")
            XCTAssertEqual((json["header"] as? [String: String])?["Authorization"], "Bearer $TOKEN$")
            XCTAssertEqual((json["header"] as? [String: String])?["Chatgpt-Account-Id"], "workspace")
            return (200, Data(#"{"status_code":200,"body":{"rate_limit":{"primary_window":{"used_percent":28,"limit_window_seconds":18000}}}}"#.utf8))
        }
        let quota = await client.quota(for: Account(id: "a", authIndex: "test-account", provider: "codex", name: "a", email: "a@example.com", accountID: "workspace"), api: .v8)
        XCTAssertNil(quota.issue); XCTAssertEqual(quota.windows.first?.remaining, 72)
    }
    func testDisabledNeverCallsProvider() async {
        let client = makeClient { _ in XCTFail("Disabled account made a network call"); return (500, Data()) }
        let quota = await client.quota(for: Account(id: "x", authIndex: "x", provider: "codex", name: "x", email: "x", disabled: true), api: .v8)
        XCTAssertTrue(quota.windows.isEmpty); XCTAssertEqual(quota.issue, "Disabled in CliProxy")
    }
}
