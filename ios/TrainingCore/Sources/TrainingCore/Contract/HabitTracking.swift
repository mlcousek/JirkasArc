// HabitTracking.swift
//
// The three per-habit fields the vault is adding to the projection
// (add-interactive-habits design D2; additive, still v1) so the phone can
// show a habit's streak and history without computing them:
//
//   streak     { current, best, unit: day|week|occurrence, lastDone }
//   history    [ { date, expected, done } ]   (84 days, oldest first)
//   adherence  { d7, d14, d30, d84 }          (percent)
//
// The vault's contract for these is still in progress, so decoding is as
// tolerant as the rest of the projection AND tolerant about the shapes
// that are not settled yet:
//
//   - `expected` / `done` may be a count (`2`) or a flag (`true`):
//     `HabitCount` keeps what was written, and the timeline resolves a flag
//     against the habit's doses per day;
//   - an adherence window may be a percent (`86`) or an object with `pct`
//     (the shape `window14` already has);
//   - a history entry without a readable `date` is dropped and counted
//     (`LossyArray`); every other field is lenient;
//   - absent fields stay `nil`, which is what switches the phone to its own
//     limited fallback (Plan/HabitTimeline.swift).
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

/// A count (`2`) or a flag (`true`), whichever the vault wrote.
public enum HabitCount: Equatable, Sendable, Decodable {
    case count(Int)
    case flag(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool first: Foundation refuses to read `true` as a number and `1`
        // as a Bool, so the order only matters for clarity.
        if let value = try? container.decode(Bool.self) {
            self = .flag(value)
        } else if let value = try? container.decode(Int.self) {
            self = .count(value)
        } else {
            let value = try container.decode(Double.self)
            guard value.isFinite, abs(value) < Double(Int32.max) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a count")
            }
            self = .count(Int(value.rounded()))
        }
    }

    /// The count, with a `true` flag read as `full`.
    public func resolved(full: Int) -> Int {
        switch self {
        case .count(let value): return max(value, 0)
        case .flag(let value): return value ? max(full, 1) : 0
        }
    }
}

public struct HabitHistoryDay: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "habit history day"

    public var date: LocalDate
    /// `nil`: the vault did not say whether the day expected the habit.
    public var expected: HabitCount?
    /// `nil`: not recorded.
    public var done: HabitCount?

    public init(date: LocalDate, expected: HabitCount? = nil, done: HabitCount? = nil) {
        self.date = date
        self.expected = expected
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case date, expected, done }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        expected = c.lenient(HabitCount.self, .expected)
        done = c.lenient(HabitCount.self, .done)
    }
}

/// Percent done of expected over the last 7, 14, 30 and 84 days.
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
        func percent(_ key: CodingKeys) -> Int? {
            let value = c.lenientInt(key) ?? c.lenient(HabitWindow.self, key)?.pct
            return value.map { min(max($0, 0), 100) }
        }
        d7 = percent(.d7)
        d14 = percent(.d14)
        d30 = percent(.d30)
        d84 = percent(.d84)
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
