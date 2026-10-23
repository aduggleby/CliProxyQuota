import Foundation

public enum ForecastLookback: Int, CaseIterable, Sendable {
    case thirty = 30, sixty = 60, oneTwenty = 120
    public var title: String { "\(rawValue)m" }
    public var seconds: TimeInterval { Double(rawValue) * 60 }
}

/// One matching quota window summed across a stable set of a provider's accounts.
/// Keys and cohort identifiers should be opaque hashes when persisted.
public struct ForecastObservation: Sendable {
    public let key: String
    public let cohort: String
    public let remaining: Double
    public let reset: Date?
    public let cycleResets: [Date]
    public init(key: String, cohort: String, remaining: Double, reset: Date?, cycleResets: [Date] = []) {
        self.key = key; self.cohort = cohort; self.remaining = remaining; self.reset = reset
        self.cycleResets = cycleResets.isEmpty ? reset.map { [$0] } ?? [] : cycleResets
    }
}

public enum UsageForecast: Equatable, Sendable {
    case learning, unavailable, inTime, runsOut(minutesBeforeReset: Int)
    public var isWarning: Bool { if case .runsOut = self { return true }; return false }
    public var message: String {
        switch self {
        case .learning: return "Learning your usage pace…"
        case .unavailable: return "Forecast waiting for fresh quota data."
        case .inTime: return "At current pace your limits will reset in time."
        case .runsOut(let minutes): return "At current pace you will run out \(minutes)m before reset."
        }
    }
}

public struct ForecastHistory: Codable, Sendable {
    private struct Sample: Codable, Sendable {
        let date: Date
        let cohort: String
        let remaining: Double
        let reset: Date?
        let cycleResets: [Date]
    }
    private var series: [String: [Sample]] = [:]
    public init() {}

    private static func sameCycles(_ a: [Date], _ b: [Date]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.timeIntervalSince($1)) <= 120 }
    }

    public mutating func record(_ observations: [ForecastObservation], at now: Date, maximumGap: TimeInterval) {
        let cutoff = now.addingTimeInterval(-86400)
        series = series.compactMapValues { samples in
            let recent = samples.filter { $0.date >= cutoff && $0.date <= now }
            return recent.isEmpty ? nil : recent
        }
        for observation in observations where observation.remaining.isFinite && observation.remaining >= 0 {
            var samples = series[observation.key] ?? []
            if let last = samples.last {
                guard now > last.date else { continue }
                let changedReset: Bool
                switch (last.reset, observation.reset) {
                case (.some(let a), .some(let b)): changedReset = abs(a.timeIntervalSince(b)) > 120
                case (.none, .none): changedReset = false
                default: changedReset = true
                }
                if last.cohort != observation.cohort || changedReset ||
                    !Self.sameCycles(last.cycleResets, observation.cycleResets) ||
                    now.timeIntervalSince(last.date) > maximumGap ||
                    observation.remaining > last.remaining + 0.5 ||
                    (last.reset.map { $0 <= now } ?? false) {
                    samples = []
                }
            }
            samples.append(Sample(date: now, cohort: observation.cohort, remaining: observation.remaining, reset: observation.reset, cycleResets: observation.cycleResets))
            series[observation.key] = Array(samples.suffix(1500))
        }
    }

    public func forecast(_ observations: [ForecastObservation], lookback: ForecastLookback,
                         now: Date, maximumGap: TimeInterval) -> UsageForecast {
        guard !observations.isEmpty else { return .unavailable }
        var pending = false
        var warnings: [(exhaustion: TimeInterval, before: Int)] = []
        for observation in observations {
            guard observation.remaining.isFinite, observation.remaining >= 0,
                  let reset = observation.reset, reset > now,
                  let samples = series[observation.key], let last = samples.last,
                  last.cohort == observation.cohort,
                  Self.sameCycles(last.cycleResets, observation.cycleResets),
                  abs(last.remaining - observation.remaining) < 0.001,
                  let lastReset = last.reset, abs(lastReset.timeIntervalSince(reset)) <= 120,
                  now >= last.date, now.timeIntervalSince(last.date) <= maximumGap else { return .unavailable }
            let cutoff = now.addingTimeInterval(-lookback.seconds)
            let boundary = samples.firstIndex(where: { $0.date >= cutoff }) ?? samples.count
            // Interpolate the horizon using one preceding neighbor. This also supports
            // a 30-minute lookback when the refresh interval is ten minutes.
            let recent = Array(samples.dropFirst(max(0, boundary - 1)))
            guard recent.count >= 4, let first = recent.first else { pending = true; continue }
            var startDate = first.date
            var startRemaining = first.remaining
            if first.date < cutoff, recent.count > 1 {
                let next = recent[1]
                let fraction = cutoff.timeIntervalSince(first.date) / next.date.timeIntervalSince(first.date)
                startRemaining += (next.remaining - first.remaining) * fraction
                startDate = cutoff
            }
            let elapsed = last.date.timeIntervalSince(startDate)
            guard elapsed >= lookback.seconds / 2 else { pending = true; continue }
            let drop = max(0, startRemaining - last.remaining)
            let rate = drop / elapsed
            let exhaustion = observation.remaining == 0 ? 0 : rate > 0 ? observation.remaining / rate : .infinity
            let untilReset = reset.timeIntervalSince(now)
            if exhaustion < untilReset {
                warnings.append((exhaustion, max(1, Int(ceil((untilReset - exhaustion) / 60)))))
            }
        }
        // A known limiting window is enough to warn; every window must be ready to claim safety.
        if let first = warnings.min(by: { $0.exhaustion < $1.exhaustion }) { return .runsOut(minutesBeforeReset: first.before) }
        return pending ? .learning : .inTime
    }
}
