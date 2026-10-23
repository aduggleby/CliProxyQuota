import XCTest
@testable import QuotaCore

final class UsageForecastTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    func observation(_ value: Double, key: String = "provider/window", cohort: String = "two-accounts", reset: Date? = nil) -> ForecastObservation {
        ForecastObservation(key: key, cohort: cohort, remaining: value, reset: reset ?? now.addingTimeInterval(8280))
    }
    func history(current: Double, perHour: Double, minutes: Int = 60, key: String = "provider/window", reset: Date? = nil) -> ForecastHistory {
        var history = ForecastHistory()
        for ago in stride(from: minutes, through: 0, by: -2) {
            history.record([observation(current + perHour * Double(ago) / 60, key: key, reset: reset)],
                           at: now.addingTimeInterval(-Double(ago) * 60), maximumGap: 300)
        }
        return history
    }
    func testCombinedAllowanceAndCombinedPaceWarnBeforeNextReset() {
        let h = history(current: 120, perHour: 90)
        let result = h.forecast([observation(120)], lookback: .sixty, now: now, maximumGap: 300)
        XCTAssertEqual(result, .runsOut(minutesBeforeReset: 58))
        XCTAssertEqual(result.message, "At current pace you will run out 58m before reset.")
    }
    func testSpareAllowanceAcrossAccountsPreventsSingleAccountWarning() {
        // One account can have 0 left while another has 100. The provider has 100 units.
        let h = history(current: 100, perHour: 20)
        XCTAssertEqual(h.forecast([observation(100)], lookback: .sixty, now: now, maximumGap: 300), .inTime)
    }
    func testIdleIntervalsCountAndFlatPaceResetsInTime() {
        let h = history(current: 80, perHour: 0)
        XCTAssertEqual(h.forecast([observation(80)], lookback: .sixty, now: now, maximumGap: 300), .inTime)
    }
    func testAveragingWindowChangesBurstEstimate() {
        var h = ForecastHistory()
        for ago in stride(from: 120, through: 0, by: -2) {
            h.record([observation(120 + 90 * Double(min(40, ago)) / 60)], at: now.addingTimeInterval(-Double(ago) * 60), maximumGap: 300)
        }
        XCTAssertEqual(h.forecast([observation(120)], lookback: .thirty, now: now, maximumGap: 300), .runsOut(minutesBeforeReset: 58))
        XCTAssertEqual(h.forecast([observation(120)], lookback: .oneTwenty, now: now, maximumGap: 300), .inTime)
    }
    func testInsufficientHistoryCannotClaimSafety() {
        let h = history(current: 80, perHour: 1, minutes: 10)
        XCTAssertEqual(h.forecast([observation(80)], lookback: .sixty, now: now, maximumGap: 300), .learning)
    }
    func testAccountChangeRequiresNewHistory() {
        var h = history(current: 80, perHour: 20)
        let added = observation(180, cohort: "three-accounts")
        h.record([added], at: now.addingTimeInterval(120), maximumGap: 300)
        XCTAssertEqual(h.forecast([added], lookback: .sixty, now: now.addingTimeInterval(120), maximumGap: 300), .learning)
    }
    func testResetAndAllowanceIncreaseRequireNewHistory() {
        for updated in [observation(100), observation(80, reset: now.addingTimeInterval(20000))] {
            var h = history(current: 80, perHour: 20)
            h.record([updated], at: now.addingTimeInterval(120), maximumGap: 300)
            XCTAssertEqual(h.forecast([updated], lookback: .sixty, now: now.addingTimeInterval(120), maximumGap: 300), .learning)
        }
    }
    func testSleepGapDoesNotBecomeConsumptionTime() {
        var h = history(current: 80, perHour: 20)
        let later = now.addingTimeInterval(3600)
        h.record([observation(50)], at: later, maximumGap: 300)
        XCTAssertEqual(h.forecast([observation(50)], lookback: .sixty, now: later, maximumGap: 300), .learning)
    }
    func testStaleOrPastResetOrChangedCurrentDataUnavailable() {
        let h = history(current: 80, perHour: 20)
        XCTAssertEqual(h.forecast([observation(80)], lookback: .sixty, now: now.addingTimeInterval(301), maximumGap: 300), .unavailable)
        XCTAssertEqual(h.forecast([observation(79)], lookback: .sixty, now: now, maximumGap: 300), .unavailable)
        XCTAssertEqual(h.forecast([observation(80, reset: now)], lookback: .sixty, now: now, maximumGap: 300), .unavailable)
        XCTAssertEqual(h.forecast([], lookback: .sixty, now: now, maximumGap: 300), .unavailable)
    }
    func testMissingResetCannotClaimSafety() {
        var h = ForecastHistory()
        let unknown = ForecastObservation(key: "missing-reset", cohort: "a", remaining: 80, reset: nil)
        h.record([unknown], at: now, maximumGap: 300)
        XCTAssertEqual(h.forecast([unknown], lookback: .sixty, now: now, maximumGap: 300), .unavailable)
    }
    func testKnownWarningWinsOverOtherWindowStillLearning() {
        var h = history(current: 120, perHour: 90)
        let weekly = observation(180, key: "weekly", reset: now.addingTimeInterval(86400))
        h.record([weekly], at: now, maximumGap: 300)
        XCTAssertEqual(h.forecast([observation(120), weekly], lookback: .sixty, now: now, maximumGap: 300), .runsOut(minutesBeforeReset: 58))
    }
    func testEveryWindowMustBeReadyForSafeVerdict() {
        var h = history(current: 120, perHour: 10)
        let weekly = observation(180, key: "weekly")
        h.record([weekly], at: now, maximumGap: 300)
        XCTAssertEqual(h.forecast([observation(120), weekly], lookback: .sixty, now: now, maximumGap: 300), .learning)
    }
    func testRoundTripHistoryAndDuplicateSamples() throws {
        var h = history(current: 120, perHour: 90)
        h.record([observation(10)], at: now, maximumGap: 300)
        let restored = try JSONDecoder().decode(ForecastHistory.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(restored.forecast([observation(120)], lookback: .sixty, now: now, maximumGap: 300), .runsOut(minutesBeforeReset: 58))
    }
    func testLaterAccountResetCannotHideBehindCombinedDrop() {
        var h = ForecastHistory()
        let earliest = now.addingTimeInterval(8280)
        let later = now.addingTimeInterval(20000)
        for ago in stride(from: 60, through: 0, by: -2) {
            h.record([ForecastObservation(key: "pool", cohort: "a-b", remaining: 120 + Double(ago),
                reset: earliest, cycleResets: [earliest, later])],
                at: now.addingTimeInterval(-Double(ago) * 60), maximumGap: 300)
        }
        // B resets, while A consumes more than B gains. The total still falls and
        // the earliest reset is unchanged, but the history must restart.
        let changed = ForecastObservation(key: "pool", cohort: "a-b", remaining: 110,
            reset: earliest, cycleResets: [earliest, later.addingTimeInterval(86400)])
        h.record([changed], at: now.addingTimeInterval(120), maximumGap: 300)
        XCTAssertEqual(h.forecast([changed], lookback: .sixty, now: now.addingTimeInterval(120), maximumGap: 300), .learning)
    }
    func testTenMinutePollingSupportsThirtyMinuteLookbackBetweenRefreshes() {
        var h = ForecastHistory()
        for ago in stride(from: 60, through: 0, by: -10) {
            h.record([observation(20 + 20 * Double(ago) / 60)],
                     at: now.addingTimeInterval(-Double(ago) * 60), maximumGap: 1500)
        }
        XCTAssertEqual(h.forecast([observation(20)], lookback: .thirty,
            now: now.addingTimeInterval(1), maximumGap: 1500), .runsOut(minutesBeforeReset: 78))
    }
    func testNonFiniteDataAndClockRollbackCannotProduceVerdict() {
        var h = ForecastHistory()
        h.record([observation(.nan)], at: now, maximumGap: 300)
        XCTAssertEqual(h.forecast([observation(.nan)], lookback: .sixty, now: now, maximumGap: 300), .unavailable)
        h = history(current: 80, perHour: 20)
        XCTAssertEqual(h.forecast([observation(80)], lookback: .sixty, now: now.addingTimeInterval(-120), maximumGap: 300), .unavailable)
    }
}
