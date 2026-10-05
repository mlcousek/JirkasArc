// HabitTracking.swift
//
// The three per-habit fields the vault added to the projection on
// 2026-10-01 (its change add-training-load-and-gates; additive, still v1;
// add-interactive-habits design D2), so the phone shows a habit's streak
// and history without computing what the vault computes:
//
//   streak     { current, best, unit: day|week|occurrence, lastDone } | null
//   history    [ { date, expected, done } ]   (84 days ending asOf)
//   adherence  { d7, d14, d30, d84: int|null } | null   (whole percents)
//
// What the vault promises (the contract's semantics 21), relied on by
// HabitTimeline:
//   - all three are filled only on an ACTIVE habit (`null` / `[]` / `null`
//     on a next or later step);
//   - `history` lists every day where something was expected or done. A
//     past expected day with nothing logged is listed with `done: 0` (the
//     streak treats a silent day as a miss); today appears once logged; a
//     day that is not listed expected nothing;
//   - `done` is the uncapped count; `expected` is 0 for a weekly-count
//     habit (its target is per week, not per day);
//   - `best` is the longest streak inside the 84 days, not a lifetime
//     record;
//   - `adherence` keeps the gate's arithmetic ("unrecorded is not zero"),
//     over complete days ending yesterday; `null` in a window where nothing
//     was expected on a recorded day.
//
// Decoding is as tolerant as the rest of the projection: a missing key, a
// `null` or a value of the wrong type reads as `nil`, a history entry
// without a readable `date` is dropped and counted (`LossyArray`), a
// negative count reads as 0 and a percent is kept inside 0...100. An absent
// `history` (an older cached file) stays `nil`, which is what switches the
// phone to its own limited fallback (Plan/HabitTimeline.swift).
//
// Nothing here is shown directly: HabitTimeline merges it with the phone's
// own ticks.
//
// Depended on by: Projection.swift (`Habit`), HabitTimeline. Tests:
// HabitTimelineTests (synthetic inline fixtures only).

import Foundation

public enum HabitStreakUnit: String, OpenEnumValue {
    /// Consecutive days.
    case day
    /// Consecutive weeks that met the habit's weekly target.
    case week
    /// Consecutive times the plan expected the habit.
    case occurrence
}

public struct HabitStreak: Equatable, Sendable, Decodable {
    public var current: Int?
    public var best: Int?
    public var unit: OpenEnum<HabitStreakUnit>?
    /// The last day with anything done.
    public var lastDone: LocalDate?

    public init(current: Int? = nil, best: Int? = nil, unit: OpenEnum<HabitStreakUnit>? = nil, lastDone: LocalDate? = nil) {
        self.current = current
        self.best = best
        self.unit = unit
        self.lastDone = lastDone
    }

    enum CodingKeys: String, CodingKey { case current, best, unit, lastDone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = c.lenientInt(.current).map { max($0, 0) }
        best = c.lenientInt(.best).map { max($0, 0) }
        unit = c.lenient(OpenEnum<HabitStreakUnit>.self, .unit)
        lastDone = c.lenient(LocalDate.self, .lastDone)
    }
}

public struct HabitHistoryDay: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "habit history day"

    public var date: LocalDate
    /// Doses expected that day (0: nothing was); `nil` when unreadable.
    public var expected: Int?
    /// Doses done, uncapped; `nil` when unreadable.
    public var done: Int?

    public init(date: LocalDate, expected: Int? = nil, done: Int? = nil) {
        self.date = date
        self.expected = expected
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case date, expected, done }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        expected = c.lenientInt(.expected).map { max($0, 0) }
        done = c.lenientInt(.done).map { max($0, 0) }
    }
}

/// Whole percents done of expected over the last 7, 14, 30 and 84 complete
/// days; `nil` where the vault has no percent for that window.
public struct HabitAdherence: Equatable, Sendable, Decodable {
    public static let windows = [7, 14, 30, 84]

    public var d7: Int?
    public var d14: Int?
    public var d30: Int?
    public var d84: Int?

    public init(d7: Int? = nil, d14: Int? = nil, d30: Int? = nil, d84: Int? = nil) {
        self.d7 = d7
        self.d14 = d14
        self.d30 = d30
        self.d84 = d84
    }

    enum CodingKeys: String, CodingKey { case d7, d14, d30, d84 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        d7 = HabitAdherence.clamped(c.lenientInt(.d7))
        d14 = HabitAdherence.clamped(c.lenientInt(.d14))
        d30 = HabitAdherence.clamped(c.lenientInt(.d30))
        d84 = HabitAdherence.clamped(c.lenientInt(.d84))
    }

    static func clamped(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 100) }
    }

    /// The vault's percent for a window of `days`; `nil` for any other.
    public func percent(days: Int) -> Int? {
        switch days {
        case 7: return d7
        case 14: return d14
        case 30: return d30
        case 84: return d84
        default: return nil
        }
    }
}
