// HabitTimeline.swift
//
// One habit, day by day, as the Habits screens need it
// (add-interactive-habits design D3-D5): the vault's history where it
// publishes one, the plan's own days where it doesn't, and the phone's own
// ticks over both. Pure and deterministic; nothing here formats text.
//
// Where a day's facts come from, in this order:
//   1. the habit's `history` entry for that date (the vault's 84 days);
//   2. the plan's day -- `habitsExpected` / `habitsDone` -- through the one
//      accessor `EffectivePlan.day(_:)` (never by walking weeks here);
//   3. nothing: the day is `unknown`.
// Then the phone's overlay: its latest `habit.tick` for that (date, habit)
// wins while it is kept (CheckInOverlay; 21 days), and its dose count
// (`HabitDoseLedger`) fills in a multi-dose day that is not complete yet.
//
// Streak rules (the owner's, design D4):
//   - expected and done            extends the run
//   - expected and missed / partly ends it
//   - not expected                 neither
//   - today, not done yet          neither (the day isn't over)
//   - unknown                      ends the COUNT but not the streak: the
//                                  run is "open-ended" (the phone ran out
//                                  of days it knows)
//
// The vault's numbers stay the truth (design D5). When it publishes
// `streak`, the phone shows that number moved by exactly what its own ticks
// change -- the run counted WITH the ticks minus the run counted WITHOUT
// them -- so a tick today extends the streak at once and an un-tick takes
// it back, and with no ticks the vault's number is shown untouched. A
// `week` streak is never recomputed (the phone doesn't know the weekly
// target rule). Adherence works the same way: the vault's percent unless a
// tick changes a day inside that window.
//
// Without the vault's fields the same functions give a FALLBACK from the
// days the phone knows (the plan's window, a few weeks), marked as an
// estimate with the number of days it covers; a window longer than that
// has no percent at all rather than a misleading one.
//
// A multi-dose habit (2x a day) and the wire format: `habit.tick` is on/off
// (decision A42). `HabitDosePolicy` turns a counter step into "keep the
// count on the phone" below the day's doses and "record done" when the last
// dose is ticked, so the vault only ever hears on or off.
//
// Depended on by: ViewModels/HabitModels.swift. Tests: HabitTimelineTests.

import Foundation

// MARK: - A day

public enum HabitDayState: String, Equatable, Sendable, CaseIterable {
    case done
    /// Some doses of a multi-dose day.
    case partly
    case missed
    case notExpected
    /// Nothing known about the day.
    case unknown
    /// Expected, not done yet, and the day isn't over (today or later).
    case open
}

public struct HabitDayRecord: Equatable, Sendable, Identifiable {
    public var id: LocalDate { date }
    public let date: LocalDate
    /// Doses expected that day; 0 when not expected or unknown.
    public let expected: Int
    /// Doses done, with the phone's tick and doses applied.
    public let done: Int
    public let state: HabitDayState
    /// What the vault (history or the plan's day) counted; `nil` when it
    /// has no count for the day.
    public let vaultDone: Int?
    /// The phone's own tick for the day, while it is kept.
    public let local: OverlayValue<Bool>?

    public init(date: LocalDate, expected: Int, done: Int, state: HabitDayState, vaultDone: Int? = nil, local: OverlayValue<Bool>? = nil) {
        self.date = date
        self.expected = expected
        self.done = done
        self.state = state
        self.vaultDone = vaultDone
        self.local = local
    }
}

// MARK: - The phone's dose counts

/// Doses done so far on a multi-dose day that is not complete yet. The
/// phone's own note: the wire only carries on/off (A42), so a count below
/// the day's doses never leaves the phone. Persisted by the app as one
/// preference value (`encoded`), pruned with the event log's retention.
public struct HabitDoseLedger: Equatable, Sendable {
    public static let empty = HabitDoseLedger()

    public private(set) var counts: [String: Int]

    public init() {
        counts = [:]
    }

    /// A stored ledger; anything unreadable is an empty one.
    public init(encoded: Data?) {
        guard let encoded, let decoded = try? JSONDecoder().decode([String: Int].self, from: encoded) else {
            counts = [:]
            return
        }
        counts = decoded.filter { $0.value > 0 }
    }

    public var encoded: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(counts)
    }

    public var isEmpty: Bool { counts.isEmpty }

    static func key(_ date: LocalDate, _ habitID: String) -> String {
        "\(date.description)|\(habitID)"
    }

    public func count(on date: LocalDate, habitID: String) -> Int? {
        counts[Self.key(date, habitID)]
    }

    /// `nil` or 0 clears the day.
    public mutating func set(_ count: Int?, on date: LocalDate, habitID: String) {
        let key = Self.key(date, habitID)
        if let count, count > 0 {
            counts[key] = count
        } else {
            counts[key] = nil
        }
    }

    /// Drops every day before `date`.
    public mutating func prune(before date: LocalDate) {
        counts = counts.filter { entry in
            guard let day = LocalDate(String(entry.key.prefix(10))) else { return false }
            return day >= date
        }
    }
}

/// What a counter step means for the phone and for the wire.
public struct HabitDoseChange: Equatable, Sendable {
    /// The on/off tick to record; `nil` when the vault needs to hear nothing.
    public let tick: Bool?
    /// The count the phone keeps for the day; `nil` clears it.
    public let partial: Int?

    public init(tick: Bool?, partial: Int?) {
        self.tick = tick
        self.partial = partial
    }
}

public enum HabitDosePolicy {
    /// From the day's `record` to `target` doses (clamped to
    /// 0...expected). `isPast`: the day is over, so "0" is a missed day the
    /// vault should hear about, not an open one.
    public static func change(from record: HabitDayRecord, to target: Int, isPast: Bool) -> HabitDoseChange {
        let expected = max(record.expected, 1)
        let goal = min(max(target, 0), expected)
        let localTick = record.local?.value
        if goal >= expected {
            return HabitDoseChange(tick: localTick == true ? nil : true, partial: nil)
        }
        let partial: Int? = goal > 0 ? goal : nil
        // Already off on the phone: only the count changes.
        if localTick == false {
            return HabitDoseChange(tick: nil, partial: partial)
        }
        let wasDone = record.done >= expected
        let vaultSaysMore = (record.vaultDone ?? 0) > goal
        let explicitMiss = goal == 0 && isPast
        let needsOff = wasDone || vaultSaysMore || explicitMiss
        return HabitDoseChange(tick: needsOff ? false : nil, partial: partial)
    }
}

// MARK: - Runs and tallies

/// A run of consecutive done occurrences, counted back from today.
public struct HabitRun: Equatable, Sendable {
    public let count: Int
    /// The run was unbroken where the known days ended, so the real one
    /// may be longer.
    public let openEnded: Bool
    /// The latest done day in the records.
    public let lastDone: LocalDate?

    public init(count: Int, openEnded: Bool, lastDone: LocalDate?) {
        self.count = count
        self.openEnded = openEnded
        self.lastDone = lastDone
    }
}

public struct HabitTally: Equatable, Sendable {
    public let done: Int
    public let expected: Int

    public init(done: Int, expected: Int) {
        self.done = done
        self.expected = expected
    }

    /// Whole percent, 0...100.
    public var pct: Int {
        expected > 0 ? min(max(done * 100 / expected, 0), 100) : 0
    }
}

public struct HabitStreakValue: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// The vault's number, untouched.
        case vault
        /// The vault's number moved by the phone's own ticks.
        case vaultWithPhoneTicks
        /// Counted on the phone from the days it knows.
        case phoneEstimate
    }

    public let current: Int
    public let best: Int
    public let unit: HabitStreakUnit
    public let lastDone: LocalDate?
    public let source: Source
    /// The count stopped where the phone's knowledge ends: "at least".
    public let isAtLeast: Bool

    public init(current: Int, best: Int, unit: HabitStreakUnit, lastDone: LocalDate?, source: Source, isAtLeast: Bool) {
        self.current = current
        self.best = best
        self.unit = unit
        self.lastDone = lastDone
        self.source = source
        self.isAtLeast = isAtLeast
    }
}

public struct HabitAdherenceValue: Equatable, Sendable, Identifiable {
    public var id: Int { days }
    public let days: Int
    /// `nil`: no percent (nothing expected, or the phone doesn't know
    /// enough days for this window).
    public let pct: Int?
    /// Counted on the phone rather than read from the vault.
    public let isEstimate: Bool

    public init(days: Int, pct: Int?, isEstimate: Bool) {
        self.days = days
        self.pct = pct
        self.isEstimate = isEstimate
    }
}

// MARK: - The timeline

public struct HabitTimeline: Equatable, Sendable {
    /// The vault's history length, and the calendar's (12 weeks).
    public static let historyDays = 84
    /// Used when the projection has no `habits.backfillDays`.
    public static let defaultBackfillDays = 14

    public let habitID: String
    public let today: LocalDate
    /// Doses a day when the habit is expected.
    public let perDay: Int
    /// Oldest first, one per day, ending today; with the phone's ticks.
    public let records: [HabitDayRecord]
    /// The same days without the phone's ticks and doses.
    public let vaultRecords: [HabitDayRecord]
    public let streak: HabitStreakValue
    /// One per window of `HabitAdherence.windows`.
    public let adherence: [HabitAdherenceValue]
    /// The vault published `history` for this habit.
    public let hasVaultHistory: Bool
    /// Days from the first known day to today, inclusive (0: none known).
    public let knownDays: Int

    public init(habit: Habit, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger = .empty, days: Int = HabitTimeline.historyDays) {
        let span = max(days, 1)
        habitID = habit.id
        self.today = today
        perDay = habit.schedule?.expectedPerDay ?? 1
        let mine = HabitTimeline.makeRecords(habit: habit, snapshot: snapshot, today: today, days: span, doses: doses, includePhone: true)
        let base = HabitTimeline.makeRecords(habit: habit, snapshot: snapshot, today: today, days: span, doses: doses, includePhone: false)
        records = mine
        vaultRecords = base
        hasVaultHistory = habit.history != nil
        let firstKnown = mine.first { $0.state != .unknown }
        let known = firstKnown.map { $0.date.days(until: today) + 1 } ?? 0
        knownDays = known
        streak = HabitTimeline.resolveStreak(habit: habit, records: mine, vaultRecords: base, today: today)
        let gateWindow = snapshot.habits.gate.windowDays ?? 14
        adherence = HabitAdherence.windows.map { window in
            HabitTimeline.resolveAdherence(
                habit: habit,
                window: window,
                gateWindow: gateWindow,
                records: mine,
                vaultRecords: base,
                today: today,
                knownDays: known
            )
        }
    }

    public func record(on date: LocalDate) -> HabitDayRecord? {
        guard let first = records.first else { return nil }
        let index = first.date.days(until: date)
        guard index >= 0, index < records.count else { return nil }
        return records[index]
    }

    // MARK: Records

    /// One record per day for `today - (days - 1) ... today`.
    static func makeRecords(habit: Habit, snapshot: TrainingSnapshot, today: LocalDate, days: Int, doses: HabitDoseLedger, includePhone: Bool) -> [HabitDayRecord] {
        var history: [LocalDate: HabitHistoryDay] = [:]
        for entry in habit.history ?? [] {
            history[entry.date] = entry
        }
        var result: [HabitDayRecord] = []
        result.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            let date = today.adding(days: -offset)
            result.append(makeRecord(habit: habit, entry: history[date], date: date, snapshot: snapshot, today: today, doses: doses, includePhone: includePhone))
        }
        return result
    }

    /// One day, which may be later than `today` (Today's day switcher).
    public static func record(for habit: Habit, on date: LocalDate, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger = .empty) -> HabitDayRecord {
        let entry = habit.history?.last { $0.date == date }
        return makeRecord(habit: habit, entry: entry, date: date, snapshot: snapshot, today: today, doses: doses, includePhone: true)
    }

    private static func makeRecord(habit: Habit, entry: HabitHistoryDay?, date: LocalDate, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger, includePhone: Bool) -> HabitDayRecord {
        let perDay = habit.schedule?.expectedPerDay ?? 1
        var expected: Int?
        var vaultDone: Int?
        if let written = entry?.expected {
            let count = written.resolved(full: perDay)
            expected = count
            vaultDone = entry?.done?.resolved(full: count > 0 ? count : perDay)
        } else if let day = snapshot.plan?.day(date) {
            expected = day.habitsExpected.contains(habit.id) ? perDay : 0
            vaultDone = day.habitsDone?[habit.id]
        }
        let tick = includePhone ? snapshot.checkIns.habitTick(on: date, habitId: habit.id) : nil
        let partial = includePhone ? doses.count(on: date, habitID: habit.id) : nil
        return resolve(date: date, today: today, perDay: perDay, expected: expected, vaultDone: vaultDone, tick: tick, partial: partial)
    }

    static func resolve(date: LocalDate, today: LocalDate, perDay: Int, expected: Int?, vaultDone: Int?, tick: OverlayValue<Bool>?, partial: Int?) -> HabitDayRecord {
        // A day the phone ticked done but no longer has a plan for (the
        // plan's window moved on): the tick itself says it was expected.
        let known: Int? = expected ?? (tick?.value == true ? perDay : nil)
        guard let doses = known else {
            return HabitDayRecord(date: date, expected: 0, done: 0, state: .unknown, vaultDone: vaultDone, local: tick)
        }
        guard doses > 0 else {
            return HabitDayRecord(date: date, expected: 0, done: max(vaultDone ?? 0, 0), state: .notExpected, vaultDone: vaultDone, local: tick)
        }
        var count: Int?
        if let tick {
            count = tick.value ? max(doses, vaultDone ?? 0) : min(partial ?? 0, doses - 1)
        } else if vaultDone != nil || partial != nil {
            count = max(vaultDone ?? 0, partial ?? 0)
        }
        let isOver = date < today
        let state: HabitDayState
        if let count {
            if count >= doses {
                state = .done
            } else if count > 0 {
                state = .partly
            } else {
                state = isOver ? .missed : .open
            }
        } else {
            state = isOver ? .unknown : .open
        }
        return HabitDayRecord(date: date, expected: doses, done: max(count ?? 0, 0), state: state, vaultDone: vaultDone, local: tick)
    }

    // MARK: Runs

    /// The run counted back from the last record (today).
    public static func currentRun(_ records: [HabitDayRecord], today: LocalDate) -> HabitRun {
        let lastDone = records.last { $0.state == .done }?.date
        var count = 0
        for record in records.reversed() {
            switch record.state {
            case .done:
                count += 1
            case .notExpected, .open:
                continue
            case .partly:
                // Today's doses can still be finished.
                if record.date >= today { continue }
                return HabitRun(count: count, openEnded: false, lastDone: lastDone)
            case .missed:
                return HabitRun(count: count, openEnded: false, lastDone: lastDone)
            case .unknown:
                return HabitRun(count: count, openEnded: true, lastDone: lastDone)
            }
        }
        return HabitRun(count: count, openEnded: true, lastDone: lastDone)
    }

    /// The longest run anywhere in the records.
    public static func bestRun(_ records: [HabitDayRecord], today: LocalDate) -> Int {
        var best = 0
        var run = 0
        for record in records {
            switch record.state {
            case .done:
                run += 1
                best = max(best, run)
            case .notExpected, .open:
                continue
            case .partly:
                if record.date >= today { continue }
                run = 0
            case .missed, .unknown:
                run = 0
            }
        }
        return best
    }

    static func resolveStreak(habit: Habit, records: [HabitDayRecord], vaultRecords: [HabitDayRecord], today: LocalDate) -> HabitStreakValue {
        let mine = currentRun(records, today: today)
        let fallbackUnit: HabitStreakUnit = habit.schedule?.kind.known == .daily ? .day : .occurrence
        guard let published = habit.streak, let vaultCurrent = published.current else {
            let best = max(bestRun(records, today: today), mine.count)
            return HabitStreakValue(
                current: mine.count,
                best: best,
                unit: fallbackUnit,
                lastDone: mine.lastDone,
                source: .phoneEstimate,
                isAtLeast: mine.openEnded && mine.count > 0
            )
        }
        let unit = published.unit?.known ?? fallbackUnit
        let base = currentRun(vaultRecords, today: today)
        var current = vaultCurrent
        var source = HabitStreakValue.Source.vault
        var isAtLeast = false
        var lastDone = published.lastDone
        if unit != .week, mine != base {
            source = .vaultWithPhoneTicks
            if mine.openEnded == base.openEnded {
                // Same anchor: the phone's ticks moved the run by exactly
                // the difference.
                current = max(vaultCurrent + mine.count - base.count, 0)
            } else {
                // The ticks broke a run that reached past the known days,
                // or joined one up to them: what the phone can count.
                current = mine.count
                isAtLeast = mine.openEnded && mine.count > 0
            }
            lastDone = mine.lastDone ?? published.lastDone
        }
        return HabitStreakValue(
            current: current,
            best: max(published.best ?? 0, current),
            unit: unit,
            lastDone: lastDone,
            source: source,
            isAtLeast: isAtLeast
        )
    }

    // MARK: Adherence

    /// Done of expected over the last `window` days up to today. A day
    /// that isn't over and isn't done, a not-expected day and an unknown
    /// day count for nothing. `nil` when nothing was expected.
    public static func tally(_ records: [HabitDayRecord], window: Int, today: LocalDate) -> HabitTally? {
        let from = today.adding(days: -(max(window, 1) - 1))
        var done = 0
        var expected = 0
        for record in records where record.date >= from && record.date <= today {
            switch record.state {
            case .done, .missed:
                expected += record.expected
                done += min(record.done, record.expected)
            case .partly:
                if record.date >= today { continue }
                expected += record.expected
                done += min(record.done, record.expected)
            case .notExpected, .unknown, .open:
                continue
            }
        }
        return expected > 0 ? HabitTally(done: done, expected: expected) : nil
    }

    static func resolveAdherence(habit: Habit, window: Int, gateWindow: Int, records: [HabitDayRecord], vaultRecords: [HabitDayRecord], today: LocalDate, knownDays: Int) -> HabitAdherenceValue {
        let mine = tally(records, window: window, today: today)
        let base = tally(vaultRecords, window: window, today: today)
        var published = habit.adherence?.percent(days: window)
        // The gate's own window is the same number when it is 14 days.
        if published == nil, window == 14, gateWindow == 14 {
            published = habit.window14?.pct.map { min(max($0, 0), 100) }
        }
        if let published {
            // The vault's percent, unless a tick changed a day in the window.
            if mine == base { return HabitAdherenceValue(days: window, pct: published, isEstimate: false) }
            return HabitAdherenceValue(days: window, pct: mine?.pct ?? published, isEstimate: true)
        }
        // Counted on the phone: only for a window it knows in full.
        guard knownDays >= window, let mine else {
            return HabitAdherenceValue(days: window, pct: nil, isEstimate: true)
        }
        return HabitAdherenceValue(days: window, pct: mine.pct, isEstimate: true)
    }
}

// MARK: - Back-fill

public enum HabitBackfill {
    /// The window in days, from the projection when it says so.
    public static func windowDays(_ habits: Habits) -> Int {
        habits.backfillDays ?? HabitTimeline.defaultBackfillDays
    }

    /// Whether a tick for `date` may still be recorded: today, any later
    /// day (decision A40), and the last `windowDays` days.
    public static func allows(_ date: LocalDate, today: LocalDate, windowDays: Int) -> Bool {
        date >= today.adding(days: -max(windowDays, 0))
    }
}
