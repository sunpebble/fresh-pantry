import Foundation

/// A consumption-cadence estimate for one item: how often it's used up and
/// whether it's likely time to rebuy. Derived from the food log (consumed
/// events) — fresh_pantry uniquely has this data, so it can be predictive where
/// pure frequency-count restock lists can't.
struct ReorderPrediction: Equatable, Sendable {
    /// Mean days between consecutive consumption events.
    let avgIntervalDays: Double
    /// Days since the most recent consumption.
    let daysSinceLast: Double

    /// elapsed / cadence — ≥ 1 means "you'd normally have used it up by now".
    var dueScore: Double { avgIntervalDays <= 0 ? 0 : daysSinceLast / avgIntervalDays }
    var isDue: Bool { dueScore >= 1 }
    /// Whole-day estimate of when the next one is due (negative = overdue).
    var daysUntilDue: Int { Int((avgIntervalDays - daysSinceLast).rounded()) }
}

/// Pure consumption-rate / reorder prediction over the food log. Needs ≥ 2
/// consumption events for an item to estimate a cadence (one event has no
/// interval). No SwiftUI / SwiftData dependency — unit-testable.
enum ReorderPredictor {
    private static let secondsPerDay = 86_400.0

    /// Estimate from a single item's consumption timestamps. nil with < 2 events
    /// or a degenerate (zero/negative) average interval.
    static func predict(consumedAt: [Date], now: Date) -> ReorderPrediction? {
        guard consumedAt.count >= 2 else { return nil }
        let sorted = consumedAt.sorted()
        var intervals: [Double] = []
        for i in 1..<sorted.count {
            intervals.append(sorted[i].timeIntervalSince(sorted[i - 1]) / secondsPerDay)
        }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0, let last = sorted.last else { return nil }
        let daysSinceLast = max(0, now.timeIntervalSince(last) / secondsPerDay)
        return ReorderPrediction(avgIntervalDays: avg, daysSinceLast: daysSinceLast)
    }

    /// Predictions keyed by lowercased item name, built from CONSUMED entries only
    /// (the cadence of using a thing up). Names with < 2 events are omitted.
    static func predictions(foodLog: [FoodLogEntry], now: Date) -> [String: ReorderPrediction] {
        var datesByName: [String: [Date]] = [:]
        for entry in foodLog where entry.deletedAt == nil && entry.isConsumed {
            let key = entry.name.trimmed.lowercased()
            guard !key.isEmpty else { continue }
            datesByName[key, default: []].append(entry.loggedAt)
        }
        var result: [String: ReorderPrediction] = [:]
        for (name, dates) in datesByName {
            if let prediction = predict(consumedAt: dates, now: now) {
                result[name] = prediction
            }
        }
        return result
    }
}
