// HabitTimeline.swift
//
// One habit, day by day, as the Habits screens need it
// (add-interactive-habits design D3-D5): the vault's history where it
// publishes one, the plan's own days where it doesn't, and the phone's own
// ticks over both. Pure and deterministic; nothing here formats text.
//
// Where a day's facts come from, in this order (`HabitDayResolver`):
//   1. the habit's `history` entry for that date (the vault's 84 days);
//   2. a day the history covers and does NOT list: the vault lists every
//      day something was expected or done, so nothing was expected;
//   3. the plan's day -- `habitsExpected` / `habitsDone` -- through the ONE
//      lookup `planDay(_:)` (never by walking weeks here). This is also
//      where today comes from until it is logged, and every day when the
//      file has no history (an older cached file): the FALLBACK;
//   4. a day before the habit started: nothing was expected;
//   5. nothing: the day is `unknown`.
// Then the phone's overlay: its latest `habit.tick` for that (date, habit)
// wins while it is kept (CheckInOverlay; 21 days; a tick the vault refused
// is not in it), and its dose count (`HabitDoseLedger`) fills in a
// multi-dose day that is not complete yet. A habit the vault measures
// itself (`source` activity or plan) takes no tick -- and the phone knows
// nothing about its days after the file's: they stay open (never a miss)
// until the next file, so its numbers are the vault's, untouched.
//
// Streak rules (the owner's, 2026-10-01; the same as the vault's):
//   - expected and done (the full dose)   extends the run
//   - expected and not done               ends it -- and a past expected
//                                         day with NOTHING logged is such
//                                         a miss, on the phone as in the
//                                         vault
//   - not expected                        neither counts nor ends
//   - today, not done yet                 neither (the day isn't over)
//   - unknown (no plan for the day)       ends the COUNT but not the
//                                         streak: the run is "open-ended"
//                                         (the phone ran out of days it
//                                         knows)
//
// The vault's numbers stay the truth (design D5). When it publishes
// `streak`, the phone shows that number moved by exactly what the phone
// knows and the file doesn't -- the run counted on the phone's view of the
// days minus the run counted on the file's view -- so a tick today extends
// the streak at once, an un-tick takes it back, a day that ended silent
// since the file was written breaks it, and with nothing new the vault's
// number is shown untouched. A `week` streak is never recounted (the phone
// doesn't know the weekly target rule). Adherence works the same way: the
// vault's percent, moved by the phone's own difference when a tick changed
// a day inside that window.
//
// The two numbers deliberately read a silent day differently, as the vault
// does: for the STREAK it is a miss, for ADHERENCE (the gate's arithmetic,
// "unrecorded is not zero") it counts for nothing. Adherence covers
// complete days only (ending yesterday), so today's tick never moves it.
//
// Without the vault's fields the same functions give a FALLBACK from the
// days the phone knows (the plan's window, a few weeks), marked as an
// estimate with the number of days it covers; a window longer than that
// has no percent at all rather than a misleading one.
//
// A multi-dose habit (2x a day) and the wire format: `habit.tick` is on/off
// (decision A42; `true` is the day's full dose). `HabitDosePolicy` turns a
// counter step into "keep the count on the phone" below the day's doses and
// "record done" when the last dose is ticked, so the vault only ever hears
// on or off.
//
// Back-fill: the vault accepts a tick for the day it was sent on and the 14
// days before, and refuses a later or an older day (`HabitBackfill`).
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
    /// A past expected day nothing was recorded on, anywhere: a miss for
    /// the streak, nothing for adherence.
    public let isSilent: Bool

    public init(date: LocalDate, expected: Int, done: Int, state: HabitDayState, vaultDone: Int? = nil, local: OverlayValue<Bool>? = nil, isSilent: Bool = false) {
        self.date = date
        self.expected = expected
        self.done = done
        self.state = state
        self.vaultDone = vaultDone
        self.local = local
        self.isSilent = isSilent
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
    /// 0...expected). `isPast`: the day is over, so "0" on a day the vault
    /// has no count for is a miss it should hear about, not an open day.
    public static func change(from record: HabitDayRecord, to target: Int, isPast: Bool) -> HabitDoseChange {
        let expected = max(record.expected, 1)
        let goal = min(max(target, 0), expected)
        let localTick = record.local?.value
        if goal >= expected {
            // Already done -- on the phone, or in the vault with no tick of
            // the phone over it: nothing more to say.
            let alreadyDone = localTick == true || (localTick == nil && (record.vaultDone ?? 0) >= expected)
            return HabitDoseChange(tick: alreadyDone ? nil : true, partial: nil)
        }
        let partial: Int? = goal > 0 ? goal : nil
        // Already off on the phone: only the count changes.
        if localTick == false {
            return HabitDoseChange(tick: nil, partial: partial)
        }
        let wasDone = record.done >= expected
        let vaultSaysMore = (record.vaultDone ?? 0) > goal
        let explicitMiss = goal == 0 && isPast && record.vaultDone == nil
        let needsOff = wasDone || vaultSaysMore || explicitMiss
        return HabitDoseChange(tick: needsOff ? false : nil, partial: partial)
    }
}

// MARK: - Runs and tallies

/// A run of consecutive done occurrences, counted back from the last day.
public struct HabitRun: Equatable, Sendable {
    public let count: Int
    /// The run was unbroken where the known days ended, so the real one
    /// may be longer.
    public let openEnded: Bool
    /// The latest day with anything done in the records.
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
        /// The vault's number moved by what the phone knows and the file
        /// doesn't: its own ticks, and days that ended since.
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
    /// Counted or moved on the phone rather than read from the vault.
    public let isEstimate: Bool

    public init(days: Int, pct: Int?, isEstimate: Bool) {
        self.days = days
        self.pct = pct
        self.isEstimate = isEstimate
    }
}

// MARK: - Where a day's facts come from

/// One habit's days, resolved as this file's header says.
struct HabitDayResolver {
    let habit: Habit
    let snapshot: TrainingSnapshot
    /// The phone's training day.
    let today: LocalDate
    /// The day the file was written for, never later than `today`: up to
    /// it the vault has judged the days; from it on only the phone has.
    let vaultToday: LocalDate
    let doses: HabitDoseLedger
    /// Doses a day when the habit is expected.
    let perDay: Int
    /// The vault measures this habit itself: a tick means nothing to it.
    let isMeasured: Bool
    /// The first day that is not over yet, as the phone sees it: its own
    /// today -- except for a measured habit, whose days after the file's
    /// only the vault can judge.
    let phoneOverBefore: LocalDate
    private let history: [LocalDate: HabitHistoryDay]
    /// From this day to the day before the file's the history is complete:
    /// a day it doesn't list expected nothing. `nil`: no history.
    private let coveredFrom: LocalDate?
    private let asOf: LocalDate

    init(habit: Habit, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger) {
        self.habit = habit
        self.snapshot = snapshot
        self.today = today
        self.doses = doses
        perDay = habit.schedule?.expectedPerDay ?? 1
        let measured = HabitBackfill.isMeasured(habit)
        isMeasured = measured
        let fileDay = snapshot.asOf ?? today
        let fileToday = min(fileDay, today)
        asOf = fileDay
        vaultToday = fileToday
        phoneOverBefore = measured ? fileToday : today
        var byDate: [LocalDate: HabitHistoryDay] = [:]
        for entry in habit.history ?? [] {
            byDate[entry.date] = entry
        }
        history = byDate
        if let entries = habit.history {
            let first = entries.first?.date
            switch habit.source?.known {
            case .dailyNote?, .activity?:
                // 84 days ending the file's day, clipped at the start.
                let windowStart = fileDay.adding(days: -(HabitTimeline.historyDays - 1))
                let from = max(windowStart, habit.started ?? windowStart)
                coveredFrom = min(from, first ?? from)
            case .plan?, nil:
                // A plan habit's history starts where the file's window
                // does, which the phone can only see from its first entry.
                coveredFrom = first
            }
        } else {
            coveredFrom = nil
        }
    }

    /// THE lookup of a date's plan day. One place on purpose: when the day
    /// skeletons land (the dates outside every written week), only this
    /// line changes.
    private func planDay(_ date: LocalDate) -> Day? {
        snapshot.plan?.day(date)
    }

    /// Doses expected (`nil`: unknown) and what the vault counted (`nil`:
    /// nothing recorded).
    func facts(on date: LocalDate) -> (expected: Int?, done: Int?) {
        let day = planDay(date)
        let planned: Int? = day.map { $0.habitsExpected.contains(habit.id) ? perDay : 0 }
        if let entry = history[date] {
            let listed: Int = entry.expected ?? planned ?? 0
            return (listed, entry.done)
        }
        if let from = coveredFrom, date >= from, date < asOf {
            return (0, nil)
        }
        if let day {
            return (planned, day.habitsDone?[habit.id])
        }
        if let started = habit.started, date < started {
            return (0, nil)
        }
        return (nil, nil)
    }

    /// The day as the phone sees it (`includePhone`: its ticks and doses,
    /// and a day is over before the phone's today) or as the file saw it
    /// (no ticks, and a day is over before the file's day).
    func record(on date: LocalDate, includePhone: Bool) -> HabitDayRecord {
        let known = facts(on: date)
        let takesTicks = includePhone && !isMeasured
        let tick = takesTicks ? snapshot.checkIns.habitTick(on: date, habitId: habit.id) : nil
        let partial = takesTicks ? doses.count(on: date, habitID: habit.id) : nil
        return HabitTimeline.resolve(
            date: date,
            overBefore: includePhone ? phoneOverBefore : vaultToday,
            perDay: perDay,
            expected: known.expected,
            vaultDone: known.done,
            tick: tick,
            partial: partial
        )
    }

    /// One record per day for `today - (days - 1) ... today`.
    func records(days: Int, includePhone: Bool) -> [HabitDayRecord] {
        var result: [HabitDayRecord] = []
        result.reserveCapacity(max(days, 0))
        for offset in stride(from: days - 1, through: 0, by: -1) {
            result.append(record(on: today.adding(days: -offset), includePhone: includePhone))
        }
        return result
    }
}

// MARK: - The timeline

public struct HabitTimeline: Equatable, Sendable {
    /// The vault's history length, and the calendar's (12 weeks).
    public static let historyDays = 84
    /// Days kept: one more than the history, so the longest adherence
    /// window (84 complete days ending yesterday) fits.
    public static let span = historyDays + 1

    public let habitID: String
    public let today: LocalDate
    /// Doses a day when the habit is expected.
    public let perDay: Int
    /// Oldest first, one per day, `span` days ending today; with the
    /// phone's ticks.
    public let records: [HabitDayRecord]
    /// The same days as the file saw them: without the phone's ticks and
    /// doses, and with the days since the file was written still open.
    public let vaultRecords: [HabitDayRecord]
    public let streak: HabitStreakValue
    /// One per window of `HabitAdherence.windows`.
    public let adherence: [HabitAdherenceValue]
    /// The vault published `history` for this habit.
    public let hasVaultHistory: Bool
    /// Days from the first day the phone knows (not before the habit
    /// started) to today, inclusive (0: none known).
    public let knownDays: Int

    public init(habit: Habit, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger = .empty) {
        let resolver = HabitDayResolver(habit: habit, snapshot: snapshot, today: today, doses: doses)
        let mine = resolver.records(days: HabitTimeline.span, includePhone: true)
        let base = resolver.records(days: HabitTimeline.span, includePhone: false)
        habitID = habit.id
        self.today = today
        perDay = resolver.perDay
        records = mine
        vaultRecords = base
        hasVaultHistory = habit.history != nil

        var knownFrom = mine.first { $0.state != .unknown }?.date
        if let first = knownFrom, let started = habit.started, started > first {
            knownFrom = started
        }
        knownDays = knownFrom.map { max($0.days(until: today) + 1, 0) } ?? 0

        streak = HabitTimeline.resolveStreak(habit: habit, records: mine, vaultRecords: base, overBefore: resolver.phoneOverBefore, vaultToday: resolver.vaultToday)
        let gateWindow = snapshot.habits.gate.windowDays ?? 14
        adherence = HabitAdherence.windows.map { window in
            HabitTimeline.resolveAdherence(habit: habit, window: window, gateWindow: gateWindow, records: mine, vaultRecords: base, today: today)
        }
    }

    public func record(on date: LocalDate) -> HabitDayRecord? {
        guard let first = records.first else { return nil }
        let index = first.date.days(until: date)
        guard index >= 0, index < records.count else { return nil }
        return records[index]
    }

    /// One day as the phone sees it; it may be later than `today` (Today's
    /// day switcher) or older than the timeline.
    public static func record(for habit: Habit, on date: LocalDate, snapshot: TrainingSnapshot, today: LocalDate, doses: HabitDoseLedger = .empty) -> HabitDayRecord {
        HabitDayResolver(habit: habit, snapshot: snapshot, today: today, doses: doses).record(on: date, includePhone: true)
    }

    // MARK: A day's state

    /// `overBefore`: the first day that is not over yet.
    static func resolve(date: LocalDate, overBefore: LocalDate, perDay: Int, expected: Int?, vaultDone: Int?, tick: OverlayValue<Bool>?, partial: Int?) -> HabitDayRecord {
        // A day the phone ticked done but no longer has a plan for (the
        // plan's window moved on): the tick itself says it was expected.
        let known: Int? = expected ?? (tick?.value == true ? max(perDay, 1) : nil)
        guard let planned = known else {
            return HabitDayRecord(date: date, expected: 0, done: 0, state: .unknown, vaultDone: vaultDone, local: tick)
        }
        guard planned > 0 else {
            // Nothing was expected. Something done anyway (a weekly-count
            // habit, an extra) shows as done; with `expected` 0 it never
            // counts for a streak or a percent.
            var extra = max(vaultDone ?? 0, 0)
            if let tick {
                extra = tick.value ? max(extra, 1) : 0
            }
            return HabitDayRecord(date: date, expected: 0, done: extra, state: extra > 0 ? .done : .notExpected, vaultDone: vaultDone, local: tick)
        }
        var count: Int?
        if let tick {
            count = tick.value ? max(planned, vaultDone ?? 0) : min(max(partial ?? 0, 0), planned - 1)
        } else if vaultDone != nil || partial != nil {
            count = max(vaultDone ?? 0, partial ?? 0)
        }
        let isOver = date < overBefore
        guard let counted = count else {
            // Nothing recorded anywhere. Once the day is over that is a
            // miss (the owner's rule, 2026-10-01).
            return HabitDayRecord(date: date, expected: planned, done: 0, state: isOver ? .missed : .open, vaultDone: vaultDone, local: tick, isSilent: isOver)
        }
        let state: HabitDayState
        if counted >= planned {
            state = .done
        } else if counted > 0 {
            state = .partly
        } else {
            state = isOver ? .missed : .open
        }
        return HabitDayRecord(date: date, expected: planned, done: max(counted, 0), state: state, vaultDone: vaultDone, local: tick)
    }

    // MARK: Runs

    /// The run counted back from the last record. `overBefore`: the first
    /// day that is not over yet (its missing doses can still be done).
    /// `started`: when the habit started, if the file says so -- a run that
    /// reaches it is complete, not open-ended.
    public static func currentRun(_ records: [HabitDayRecord], overBefore: LocalDate, started: LocalDate? = nil) -> HabitRun {
        let lastDone = records.last { $0.done > 0 }?.date
        var count = 0
        for record in records.reversed() {
            switch record.state {
            case .done:
                if record.expected > 0 { count += 1 }
            case .notExpected, .open:
                continue
            case .partly:
                if record.date >= overBefore { continue }
                return HabitRun(count: count, openEnded: false, lastDone: lastDone)
            case .missed:
                return HabitRun(count: count, openEnded: false, lastDone: lastDone)
            case .unknown:
                return HabitRun(count: count, openEnded: true, lastDone: lastDone)
            }
        }
        // Out of days: the run may reach further back, unless the habit
        // started inside them.
        var reachedStart = records.isEmpty
        if let first = records.first, let started, first.date <= started {
            reachedStart = true
        }
        return HabitRun(count: count, openEnded: !reachedStart, lastDone: lastDone)
    }

    /// The longest run anywhere in the records.
    public static func bestRun(_ records: [HabitDayRecord], overBefore: LocalDate) -> Int {
        var best = 0
        var run = 0
        for record in records {
            switch record.state {
            case .done:
                if record.expected > 0 {
                    run += 1
                    best = max(best, run)
                }
            case .notExpected, .open:
                continue
            case .partly:
                if record.date >= overBefore { continue }
                run = 0
            case .missed, .unknown:
                run = 0
            }
        }
        return best
    }

    /// `overBefore`: the first day not over yet in `records` (the phone's
    /// view); `vaultToday`: the same for `vaultRecords` (the file's).
    static func resolveStreak(habit: Habit, records: [HabitDayRecord], vaultRecords: [HabitDayRecord], overBefore: LocalDate, vaultToday: LocalDate) -> HabitStreakValue {
        let mine = currentRun(records, overBefore: overBefore, started: habit.started)
        let fallbackUnit: HabitStreakUnit = habit.schedule?.kind.known == .daily ? .day : .occurrence
        guard let published = habit.streak, let vaultCurrent = published.current else {
            let best = max(bestRun(records, overBefore: overBefore), mine.count)
            return HabitStreakValue(
                current: mine.count,
                best: best,
                unit: fallbackUnit,
                lastDone: mine.lastDone,
                source: .phoneEstimate,
                isAtLeast: mine.openEnded && mine.count > 0
            )
        }
        let unit: HabitStreakUnit
        let recountable: Bool
        switch published.unit {
        case .known(let known)?:
            unit = known
            // The phone doesn't know the weekly target rule.
            recountable = known != .week
        case .unknown?:
            // A unit this build doesn't know: a plain count, never moved.
            unit = .occurrence
            recountable = false
        case nil:
            unit = fallbackUnit
            recountable = true
        }
        let base = currentRun(vaultRecords, overBefore: vaultToday, started: habit.started)
        var current = vaultCurrent
        var source = HabitStreakValue.Source.vault
        var isAtLeast = false
        if recountable, mine.count != base.count || mine.openEnded != base.openEnded {
            source = .vaultWithPhoneTicks
            if mine.openEnded == base.openEnded {
                // Same anchor: the run moved by exactly the difference.
                current = max(vaultCurrent + mine.count - base.count, 0)
            } else {
                // A run that reached past the known days was broken, or
                // one was joined up to them: what the phone can count.
                current = mine.count
                isAtLeast = mine.openEnded && mine.count > 0
            }
        }
        return HabitStreakValue(
            current: current,
            best: max(published.best ?? 0, current),
            unit: unit,
            lastDone: mine.lastDone ?? published.lastDone,
            source: source,
            isAtLeast: isAtLeast
        )
    }

    // MARK: Adherence

    /// Done of expected over the `window` complete days ending yesterday
    /// -- the gate's arithmetic: a day's doses capped at what it expected;
    /// a not-expected or unknown day and a past day nothing was recorded
    /// on count for nothing. `nil` when nothing counts.
    public static func tally(_ records: [HabitDayRecord], window: Int, today: LocalDate) -> HabitTally? {
        let from = today.adding(days: -max(window, 1))
        var done = 0
        var expected = 0
        for record in records where record.date >= from && record.date < today {
            guard record.expected > 0, !record.isSilent else { continue }
            switch record.state {
            case .done, .partly, .missed:
                expected += record.expected
                done += min(record.done, record.expected)
            case .notExpected, .unknown, .open:
                continue
            }
        }
        return expected > 0 ? HabitTally(done: done, expected: expected) : nil
    }

    static func resolveAdherence(habit: Habit, window: Int, gateWindow: Int, records: [HabitDayRecord], vaultRecords: [HabitDayRecord], today: LocalDate) -> HabitAdherenceValue {
        let mine = tally(records, window: window, today: today)
        let base = tally(vaultRecords, window: window, today: today)

        // What the vault says for this window. Without `adherence`, the
        // gate's own window is the same number when it is 14 days.
        var published: Int?
        var isPublished = false
        if let adherence = habit.adherence {
            published = adherence.percent(days: window)
            isPublished = true
        } else if window == 14, gateWindow == 14, let pct = habit.window14?.pct {
            published = min(max(pct, 0), 100)
            isPublished = true
        }
        if isPublished {
            guard let mine, mine != base else {
                return HabitAdherenceValue(days: window, pct: published, isEstimate: false)
            }
            // A tick changed a day inside the window: the vault's percent
            // moved by what the phone's own count moved.
            var pct = mine.pct
            if let published, let base {
                pct = min(max(published + mine.pct - base.pct, 0), 100)
            }
            return HabitAdherenceValue(days: window, pct: pct, isEstimate: true)
        }

        // Counted on the phone: only for a window it knows in full.
        let from = today.adding(days: -max(window, 1))
        let start = max(from, habit.started ?? from)
        var knowsAll = false
        if let first = records.first, first.date <= start {
            knowsAll = !records.contains { $0.date >= start && $0.date < today && $0.state == .unknown }
        }
        guard knowsAll, let mine else {
            return HabitAdherenceValue(days: window, pct: nil, isEstimate: true)
        }
        return HabitAdherenceValue(days: window, pct: mine.pct, isEstimate: true)
    }
}

// MARK: - Back-fill

public enum HabitBackfill {
    /// How many days back the vault still accepts a tick (its
    /// `HABIT_BACKFILL_DAYS`).
    public static let windowDays = 14

    /// Whether a tick for `date` may be recorded: today and the last
    /// `windowDays` days. The vault refuses a later day and an older one.
    public static func allows(_ date: LocalDate, today: LocalDate) -> Bool {
        date <= today && date >= today.adding(days: -windowDays)
    }

    /// The vault measures the habit from activities or the plan; only a
    /// daily-note habit takes ticks. An unknown or absent `source` is
    /// treated as tickable (the vault ignores a tick it has no use for).
    public static func isMeasured(_ habit: Habit) -> Bool {
        switch habit.source?.known {
        case .activity?, .plan?: return true
        case .dailyNote?, nil: return false
        }
    }
}
