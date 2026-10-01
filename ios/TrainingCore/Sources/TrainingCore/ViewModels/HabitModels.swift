// HabitModels.swift
//
// The interactive habits as pure view models (add-interactive-habits design
// D6-D8; spec training-habits). The owner asked for streaks, a done / not
// done check, logging and a log history; before this the app only listed
// the ladder. Everything the three surfaces draw comes from `HabitsBuilder`:
//
//   - `screen()`        the Habits screen: the ladder as steps --
//                       established (a later step is already active),
//                       current, locked with what unlocks it -- each active
//                       habit with its streak and today's state;
//   - `detail(_:)`      one habit: today's control, the current and best
//                       streak, adherence over 7/14/30/84 days, a 12-week
//                       calendar (done, partly, missed, not planned, no
//                       record; today open), the recent entries, and how
//                       far back a day may still be filled in;
//   - `dayControl`      the control for one day: today's big one, the
//                       calendar's selected day (back-fill), a row of
//                       Today's card. It says whether the day can be
//                       changed and why not;
//   - `todayChecks`     Today's Habits card: per habit the check, its
//                       streak, and whether everything expected is done.
//
// The numbers are HabitTimeline's (Plan/HabitTimeline.swift): the vault's
// streak, history and adherence where it publishes them, the phone's own
// limited count where it doesn't -- said so on the screen -- and the
// phone's ticks over both. This file only words them.
//
// A control never records anything: the app turns `change(to:)` into a
// `habit.tick` through the one recorder (TrainingModel), and nothing is
// offered unless `TrainingCapabilities.canTickHabits`.
//
// Today's card keeps `HabitsCardModel` (HabitsCardModel.swift) for its
// rows, step and next step; this adds the checks beside it.
//
// Depended on by: the app's Habits/ views, TickHabitIntent. Tests:
// HabitModelTests.

import Foundation

// MARK: - A day's control

public struct HabitDayControlModel: Equatable, Sendable, Identifiable {
    public var id: String { "\(habitID)|\(date.description)" }
    public let habitID: String
    public let label: String
    public let date: LocalDate
    /// "Today" or "Tue 20 Oct".
    public let dateText: String
    public let isToday: Bool
    /// The day is over (a back-fill).
    public let isPast: Bool
    public let record: HabitDayRecord
    /// Doses the day expects (0: not expected or unknown).
    public let expected: Int
    /// Doses done, never more than `expected`.
    public let done: Int
    public let state: HabitDayState
    public let isMultiDose: Bool
    public let canRecord: Bool
    /// Why the day can't be changed; `nil` when it can.
    public let lockedText: String?
    /// "Done", "1 of 2", "Not done yet", "Missed", "Not planned", "No record".
    public let stateText: String
    /// The phone's tick is not uploaded yet.
    public let isPending: Bool
    /// "Saved on phone" / "Sent" / "Received by the vault" for the phone's tick.
    public let deliveryText: String?
    /// "Mark done" / "Mark not done": the back-fill buttons.
    public let markDoneText: String
    public let markNotDoneText: String
    /// "One more" / "One fewer": VoiceOver for a multi-dose counter.
    public let addDoseText: String
    public let removeDoseText: String

    public var isDone: Bool { state == .done }

    /// What one tap asks for: the next dose, or one back from complete (so
    /// a single-dose habit toggles and a mis-tap never wipes a whole day).
    public var tapTarget: Int {
        done >= expected ? max(expected - 1, 0) : done + 1
    }

    /// The step to `target` doses as the phone's count and the wire's tick.
    public func change(to target: Int) -> HabitDoseChange {
        HabitDosePolicy.change(from: record, to: target, isPast: isPast)
    }

    /// Done (every dose) or not done (none).
    public func change(done: Bool) -> HabitDoseChange {
        change(to: done ? max(expected, 1) : 0)
    }

    /// "Mark done" would change something.
    public var canMarkDone: Bool {
        canRecord && !isDone
    }

    /// "Mark not done" would change something: a tick to record, or the
    /// phone's dose count to clear.
    public var canMarkNotDone: Bool {
        canRecord && (change(done: false).tick != nil || done > 0)
    }
}

// MARK: - Streak, adherence

public struct HabitStreakModel: Equatable, Sendable {
    public let current: Int
    public let best: Int
    public let unit: HabitStreakUnit
    /// "5 days in a row" / "No streak yet".
    public let currentText: String
    /// "Best: 12".
    public let bestText: String
    /// "12 days in a row", for the best figure's caption.
    public let bestRunText: String
    /// "Current streak" / "Best streak".
    public let currentCaption: String
    public let bestCaption: String
    /// The flame is lit.
    public let isLit: Bool
    /// "Last done Tue 20 Oct".
    public let lastDoneText: String?
    /// Counted on the phone, and over how many days.
    public let estimateText: String?
    /// The count stopped where the phone's knowledge ends.
    public let mayBeLongerText: String?
}

public struct HabitAdherenceTileModel: Equatable, Sendable, Identifiable {
    public var id: Int { days }
    public let days: Int
    /// "7 d".
    public let title: String
    /// "86 %" or an en dash.
    public let valueText: String
    public let fraction: Double?
    /// At or above the ladder's gate; `nil` without a percent or a gate.
    public let meetsGate: Bool?
    public let accessibilityLabel: String
}

// MARK: - Calendar and log

public struct HabitCalendarCellModel: Equatable, Sendable, Identifiable {
    public var id: LocalDate { date }
    public let date: LocalDate
    /// The day of the month.
    public let dayText: String
    /// `nil`: a day after today.
    public let state: HabitDayState?
    public let isToday: Bool
    public let isPending: Bool
    /// Inside the back-fill window (and not after today).
    public let isInBackfillWindow: Bool
    public let accessibilityLabel: String
}

public struct HabitCalendarWeekModel: Equatable, Sendable, Identifiable {
    public var id: LocalDate { monday }
    public let monday: LocalDate
    /// "7 Oct": the week's Monday.
    public let label: String
    public let cells: [HabitCalendarCellModel]
}

public struct HabitLegendItemModel: Equatable, Sendable, Identifiable {
    public var id: String { state.rawValue }
    public let state: HabitDayState
    public let text: String
}

public struct HabitCalendarModel: Equatable, Sendable {
    /// "Last 12 weeks".
    public let title: String
    /// Monday first.
    public let weekdayHeaders: [String]
    /// Oldest first; twelve.
    public let weeks: [HabitCalendarWeekModel]
    public let legend: [HabitLegendItemModel]
    /// "Tap a day to fill it in. Back-fill window: 14 d."; `nil` when the
    /// phone can't record.
    public let hint: String?
}

public struct HabitLogEntryModel: Equatable, Sendable, Identifiable {
    public var id: LocalDate { date }
    public let date: LocalDate
    public let dateText: String
    public let state: HabitDayState
    public let stateText: String
    /// The phone's own tick: "Saved on phone" / "Sent" / "Received by the vault".
    public let deliveryText: String?
}

// MARK: - A habit

public enum HabitStepKind: String, Equatable, Sendable {
    /// Active, and a later step is active too: this one is kept running.
    case established
    /// The highest active step.
    case current
    /// Not started: next or later.
    case locked
}

public struct HabitStepModel: Equatable, Sendable, Identifiable {
    public let id: String
    /// "Step 2".
    public let stepText: String
    public let icon: String?
    public let label: String
    public let dose: String?
    public let schedule: String?
    public let kind: HabitStepKind
    /// "Established" / "Current step" / "Locked".
    public let kindText: String
    /// Locked: what unlocks it.
    public let unlockText: String?
    /// "Started 20 Sept" / "Earliest start 28 Oct".
    public let dateText: String?
    /// "Gate met: ..." on the current step when the vault says so.
    public let gateMetText: String?
    /// Active steps only.
    public let streak: HabitStreakModel?
    /// Active steps the plan expects today.
    public let today: HabitDayControlModel?
    /// "18 of 24 · 75 %" for an active step.
    public let adherence: String?
    public let fraction: Double?
    public let accessibilityLabel: String
}

public struct HabitsScreenModel: Equatable, Sendable {
    /// "Step 2 of 6".
    public let stepText: String?
    /// "Gate: 80 % · 14-day window".
    public let gateText: String?
    /// "1 of 2 done today"; `nil` when today expects none.
    public let progressText: String?
    public let steps: [HabitStepModel]
    /// "No habits in this plan".
    public let emptyText: String?
}

public struct HabitDetailModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let icon: String?
    public let label: String
    public let dose: String?
    public let why: String?
    public let schedule: String?
    public let kind: HabitStepKind
    public let kindText: String
    public let unlockText: String?
    public let dateText: String?
    public let gateMetText: String?
    /// Today's control; `nil` for a locked habit.
    public let today: HabitDayControlModel?
    public let streak: HabitStreakModel
    /// "Adherence".
    public let adherenceTitle: String
    public let adherence: [HabitAdherenceTileModel]
    /// Why a longer window has no percent yet.
    public let adherenceNote: String?
    /// "Gate: 80 % · 14-day window".
    public let gateText: String?
    public let calendar: HabitCalendarModel
    /// "Recent entries".
    public let logTitle: String
    /// Newest first.
    public let log: [HabitLogEntryModel]
    /// "Nothing logged yet".
    public let logEmptyText: String?
    public let backfillDays: Int
}

// MARK: - Today's card

public struct HabitCheckModel: Equatable, Sendable, Identifiable {
    public let id: String
    /// The shown day's control; `nil` when the plan doesn't expect the
    /// habit that day.
    public let control: HabitDayControlModel?
    public let streakCount: Int
    /// "5 days in a row" / "No streak yet".
    public let streakText: String
    public let streakIsLit: Bool
}

public struct HabitChecksModel: Equatable, Sendable {
    public let date: LocalDate
    public let checks: [String: HabitCheckModel]
    /// Habits the shown day expects, and how many of them are complete (a
    /// multi-dose habit counts once every dose is done).
    public let expectedCount: Int
    public let doneCount: Int
    /// "1 of 2 done today"; `nil` when the day expects none.
    public let progressText: String?
    /// The day expects habits and every one is done.
    public let allDone: Bool
    /// "All of today's habits done".
    public let allDoneText: String

    public func check(_ habitID: String) -> HabitCheckModel? {
        checks[habitID]
    }
}

// MARK: - Builder

public struct HabitsBuilder: Sendable {
    /// Entries in a habit's "Recent entries".
    public static let logLimit = 14
    /// Weeks in the calendar.
    public static let calendarWeeks = 12

    public let source: TrainingSource
    public let format: TrainingFormatting
    /// The current training day.
    public let today: LocalDate
    /// The phone's dose counts for multi-dose days.
    public let doses: HabitDoseLedger

    public init(source: TrainingSource, language: TrainingLanguage, today: LocalDate, doses: HabitDoseLedger = .empty) {
        self.source = source
        self.format = TrainingFormatting(language: language, zones: source.snapshot?.athlete.hrZones)
        self.today = today
        self.doses = doses
    }

    private var text: TrainingText { format.text }

    private func label(_ habit: Habit) -> String {
        habit.label.resolvedText(format.language) ?? habit.id
    }

    private func timeline(_ habit: Habit, _ snapshot: TrainingSnapshot) -> HabitTimeline {
        HabitTimeline(habit: habit, snapshot: snapshot, today: today, doses: doses)
    }

    // MARK: Words

    func stateText(_ record: HabitDayRecord) -> String {
        switch record.state {
        case .done: return text(.statusDone)
        case .partly: return text.format(.habitDoseCount, min(record.done, record.expected), record.expected)
        case .missed: return text(.statusMissed)
        case .notExpected: return text(.habitNotPlanned)
        case .unknown: return text(.habitNoRecord)
        case .open: return text(.habitNotDoneYet)
        }
    }

    func runText(_ count: Int, unit: HabitStreakUnit) -> String {
        guard count > 0 else { return text(.habitStreakNone) }
        switch unit {
        case .day: return text.format(.habitStreakDays, count)
        case .week: return text.format(.habitStreakWeeks, count)
        case .occurrence: return text.format(.habitStreakTimes, count)
        }
    }

    func streakModel(_ timeline: HabitTimeline) -> HabitStreakModel {
        let value = timeline.streak
        var estimate: String?
        if value.source == .phoneEstimate, timeline.knownDays > 0 {
            estimate = text.format(.habitEstimateNote, timeline.knownDays)
        }
        return HabitStreakModel(
            current: value.current,
            best: value.best,
            unit: value.unit,
            currentText: runText(value.current, unit: value.unit),
            bestText: text.format(.habitStreakBest, value.best),
            bestRunText: runText(value.best, unit: value.unit),
            currentCaption: text(.habitStreakCurrentCaption),
            bestCaption: text(.habitStreakBestCaption),
            isLit: value.current > 0,
            lastDoneText: value.lastDone.map { text.format(.habitStreakLastDone, format.dates.short($0)) },
            estimateText: estimate,
            mayBeLongerText: value.isAtLeast ? text(.habitStreakMayBeLonger) : nil
        )
    }

    // MARK: A day

    /// The control for `habitID` on `date`; `nil` for an unknown habit or
    /// without a plan.
    public func dayControl(habitID: String, date: LocalDate) -> HabitDayControlModel? {
        guard let snapshot = source.snapshot, let habit = snapshot.habits.habit(habitID) else { return nil }
        let record = HabitTimeline.record(for: habit, on: date, snapshot: snapshot, today: today, doses: doses)
        return control(habit: habit, record: record, snapshot: snapshot)
    }

    func control(habit: Habit, record: HabitDayRecord, snapshot: TrainingSnapshot) -> HabitDayControlModel {
        let window = HabitBackfill.windowDays(snapshot.habits)
        var locked: String?
        if !snapshot.capabilities.canTickHabits {
            locked = text(.habitLockedReadOnly)
        } else if record.state == .unknown {
            locked = text(.habitLockedUnknown)
        } else if record.state == .notExpected {
            locked = text(.habitLockedNotPlanned)
        } else if !HabitBackfill.allows(record.date, today: today, windowDays: window) {
            locked = text.format(.habitLockedWindow, window)
        }
        let isToday = record.date == today
        return HabitDayControlModel(
            habitID: habit.id,
            label: label(habit),
            date: record.date,
            dateText: isToday ? text(.today) : format.dates.short(record.date),
            isToday: isToday,
            isPast: record.date < today,
            record: record,
            expected: record.expected,
            done: min(record.done, record.expected),
            state: record.state,
            isMultiDose: record.expected > 1,
            canRecord: locked == nil,
            lockedText: locked,
            stateText: stateText(record),
            isPending: record.local?.delivery == .savedOnPhone,
            deliveryText: format.deliveryLine(record.local?.delivery),
            markDoneText: text(.habitMarkDone),
            markNotDoneText: text(.habitMarkNotDone),
            addDoseText: text(.habitDoseAdd),
            removeDoseText: text(.habitDoseRemove)
        )
    }

    // MARK: The screen

    private struct StepFacts {
        let kind: HabitStepKind
        let kindText: String
        let unlockText: String?
        let dateText: String?
        let gateMetText: String?
    }

    private func stepFacts(_ habit: Habit, index: Int, habits: Habits) -> StepFacts {
        let currentIndex = habits.ladder.lastIndex { $0.state?.known == .active }
        let isActive = habit.state?.known == .active
        let kind: HabitStepKind
        if isActive {
            kind = index == currentIndex ? .current : .established
        } else {
            kind = .locked
        }
        let kindText: String
        switch kind {
        case .established: kindText = text(.habitStepEstablished)
        case .current: kindText = text(.habitStepCurrent)
        case .locked: kindText = text(.habitStepLocked)
        }
        var unlock: String?
        if kind == .locked {
            let current = currentIndex.map { habits.ladder[$0] }
            if habit.state?.known == .next, current?.gateMet == true {
                unlock = text(.habitGateMet)
            } else if habit.state?.known == .next, let current, let pct = habits.gate.adherencePct {
                unlock = text.format(.habitUnlockWhen, label(current), pct, habits.gate.windowDays ?? 14)
            } else if index > 0 {
                unlock = text.format(.habitUnlockAfter, label(habits.ladder[index - 1]))
            }
        }
        var dateText: String?
        if let started = habit.started {
            dateText = text.format(.habitStarted, format.dates.dayMonth(started))
        } else if let earliest = habit.earliest {
            dateText = text.format(.habitEarliest, format.dates.dayMonth(earliest))
        }
        return StepFacts(
            kind: kind,
            kindText: kindText,
            unlockText: unlock,
            dateText: dateText,
            gateMetText: kind == .current && habit.gateMet == true ? text(.habitGateMet) : nil
        )
    }

    public func screen() -> HabitsScreenModel {
        guard let snapshot = source.snapshot, !snapshot.habits.ladder.isEmpty else {
            return HabitsScreenModel(stepText: nil, gateText: nil, progressText: nil, steps: [], emptyText: text(.habitsNone))
        }
        let habits = snapshot.habits
        var gateText: String?
        if let pct = habits.gate.adherencePct {
            gateText = text.format(.habitGate, pct, habits.gate.windowDays ?? 14)
        }
        let currentIndex = habits.ladder.lastIndex { $0.state?.known == .active }
        let stepText = currentIndex.map { text.format(.habitStepOf, $0 + 1, habits.ladder.count) }

        var expectedToday = 0
        var doneToday = 0
        var steps: [HabitStepModel] = []
        for (index, habit) in habits.ladder.enumerated() {
            let facts = stepFacts(habit, index: index, habits: habits)
            var streak: HabitStreakModel?
            var control: HabitDayControlModel?
            var adherence: String?
            if facts.kind != .locked {
                let line = timeline(habit, snapshot)
                streak = streakModel(line)
                adherence = HabitText.adherence(habit.window14, gate: habits.gate, text: text)
                if let record = line.records.last, record.expected > 0 {
                    control = self.control(habit: habit, record: record, snapshot: snapshot)
                    expectedToday += 1
                    if record.state == .done { doneToday += 1 }
                }
            }
            let name = label(habit)
            let spoken = [name, facts.kindText, streak?.currentText, control?.stateText, facts.unlockText]
                .compactMap { $0 }
                .joined(separator: ", ")
            steps.append(HabitStepModel(
                id: habit.id,
                stepText: text.format(.habitStepNumber, index + 1),
                icon: habit.icon,
                label: name,
                dose: habit.dose.resolvedText(format.language),
                schedule: format.schedule.line(habit.schedule),
                kind: facts.kind,
                kindText: facts.kindText,
                unlockText: facts.unlockText,
                dateText: facts.dateText,
                gateMetText: facts.gateMetText,
                streak: streak,
                today: control,
                adherence: adherence,
                fraction: habit.window14?.pct.map { Double(min(max($0, 0), 100)) / 100 },
                accessibilityLabel: spoken
            ))
        }
        return HabitsScreenModel(
            stepText: stepText,
            gateText: gateText,
            progressText: expectedToday > 0 ? text.format(.habitsDoneToday, doneToday, expectedToday) : nil,
            steps: steps,
            emptyText: nil
        )
    }

    // MARK: One habit

    public func detail(habitID: String) -> HabitDetailModel? {
        guard let snapshot = source.snapshot,
              let index = snapshot.habits.ladder.firstIndex(where: { $0.id == habitID })
        else { return nil }
        let habits = snapshot.habits
        let habit = habits.ladder[index]
        let facts = stepFacts(habit, index: index, habits: habits)
        let line = timeline(habit, snapshot)
        let window = HabitBackfill.windowDays(habits)
        let canRecord = snapshot.capabilities.canTickHabits && facts.kind != .locked

        var control: HabitDayControlModel?
        if facts.kind != .locked, let record = line.records.last {
            control = self.control(habit: habit, record: record, snapshot: snapshot)
        }

        let gate = habits.gate.adherencePct
        let tiles = line.adherence.map { value -> HabitAdherenceTileModel in
            let title = text.format(.habitWindowDays, value.days)
            let valueText = value.pct.map { text.format(.habitPct, $0) } ?? "–"
            var meetsGate: Bool?
            if let pct = value.pct, let gate {
                meetsGate = pct >= gate
            }
            return HabitAdherenceTileModel(
                days: value.days,
                title: title,
                valueText: valueText,
                fraction: value.pct.map { Double($0) / 100 },
                meetsGate: meetsGate,
                accessibilityLabel: "\(title): \(value.pct == nil ? text(.habitNoRecord) : valueText)"
            )
        }
        let hasGap = line.adherence.contains { $0.pct == nil }
        var gateText: String?
        if let gate {
            gateText = text.format(.habitGate, gate, habits.gate.windowDays ?? 14)
        }

        let entries = line.records.reversed()
            .filter { $0.state == .done || $0.state == .partly || $0.state == .missed }
            .prefix(Self.logLimit)
            .map { record in
                HabitLogEntryModel(
                    date: record.date,
                    dateText: format.dates.short(record.date),
                    state: record.state,
                    stateText: stateText(record),
                    deliveryText: format.deliveryLine(record.local?.delivery)
                )
            }

        return HabitDetailModel(
            id: habit.id,
            icon: habit.icon,
            label: label(habit),
            dose: habit.dose.resolvedText(format.language),
            why: habit.why.resolvedText(format.language),
            schedule: format.schedule.line(habit.schedule),
            kind: facts.kind,
            kindText: facts.kindText,
            unlockText: facts.unlockText,
            dateText: facts.dateText,
            gateMetText: facts.gateMetText,
            today: control,
            streak: streakModel(line),
            adherenceTitle: text(.habitAdherenceTitle),
            adherence: tiles,
            adherenceNote: hasGap && !line.hasVaultHistory ? text(.habitAdherencePartial) : nil,
            gateText: gateText,
            calendar: calendar(line, backfillDays: window, canRecord: canRecord),
            logTitle: text(.habitLogTitle),
            log: Array(entries),
            logEmptyText: entries.isEmpty ? text(.habitLogEmpty) : nil,
            backfillDays: window
        )
    }

    /// Twelve Monday-first weeks ending with today's week.
    func calendar(_ line: HabitTimeline, backfillDays: Int, canRecord: Bool) -> HabitCalendarModel {
        let lastMonday = ISOWeek(containing: today).monday
        let firstMonday = lastMonday.adding(days: -7 * (Self.calendarWeeks - 1))
        var weeks: [HabitCalendarWeekModel] = []
        for weekIndex in 0..<Self.calendarWeeks {
            let monday = firstMonday.adding(days: 7 * weekIndex)
            var cells: [HabitCalendarCellModel] = []
            for dayIndex in 0..<7 {
                let date = monday.adding(days: dayIndex)
                let record = date > today ? nil : line.record(on: date)
                let state: HabitDayState? = date > today ? nil : (record?.state ?? .unknown)
                let stateName = record.map { stateText($0) } ?? (date > today ? "" : text(.habitNoRecord))
                let dateName = format.dates.short(date)
                cells.append(HabitCalendarCellModel(
                    date: date,
                    dayText: String(date.day),
                    state: state,
                    isToday: date == today,
                    isPending: record?.local?.delivery == .savedOnPhone,
                    isInBackfillWindow: date <= today && HabitBackfill.allows(date, today: today, windowDays: backfillDays),
                    accessibilityLabel: stateName.isEmpty ? dateName : text.format(.habitDayA11y, dateName, stateName)
                ))
            }
            weeks.append(HabitCalendarWeekModel(monday: monday, label: format.dates.dayMonth(monday), cells: cells))
        }
        let legend = [
            HabitLegendItemModel(state: .done, text: text(.statusDone)),
            HabitLegendItemModel(state: .partly, text: text(.habitPartly)),
            HabitLegendItemModel(state: .missed, text: text(.statusMissed)),
            HabitLegendItemModel(state: .notExpected, text: text(.habitNotPlanned)),
            HabitLegendItemModel(state: .unknown, text: text(.habitNoRecord))
        ]
        return HabitCalendarModel(
            title: text(.habitHistoryTitle),
            weekdayHeaders: format.dates.weekdayHeaders,
            weeks: weeks,
            legend: legend,
            hint: canRecord ? text.format(.habitBackfillHint, backfillDays) : nil
        )
    }

    // MARK: Today's card

    /// The checks for Today's Habits card on `date` (the day switcher's
    /// day): every active habit and every habit the day expects.
    public func todayChecks(on date: LocalDate) -> HabitChecksModel {
        let allDoneText = text(.habitAllDoneToday)
        guard let snapshot = source.snapshot else {
            return HabitChecksModel(date: date, checks: [:], expectedCount: 0, doneCount: 0, progressText: nil, allDone: false, allDoneText: allDoneText)
        }
        var checks: [String: HabitCheckModel] = [:]
        var expected = 0
        var done = 0
        for habit in snapshot.habits.ladder {
            let record = HabitTimeline.record(for: habit, on: date, snapshot: snapshot, today: today, doses: doses)
            let isExpected = record.expected > 0
            guard habit.state?.known == .active || isExpected else { continue }
            let streak = timeline(habit, snapshot).streak
            if isExpected {
                expected += 1
                if record.state == .done { done += 1 }
            }
            checks[habit.id] = HabitCheckModel(
                id: habit.id,
                control: isExpected ? control(habit: habit, record: record, snapshot: snapshot) : nil,
                streakCount: streak.current,
                streakText: runText(streak.current, unit: streak.unit),
                streakIsLit: streak.current > 0
            )
        }
        return HabitChecksModel(
            date: date,
            checks: checks,
            expectedCount: expected,
            doneCount: done,
            progressText: expected > 0 ? text.format(.habitsDoneToday, done, expected) : nil,
            allDone: expected > 0 && done == expected,
            allDoneText: allDoneText
        )
    }
}

// MARK: - Shortcuts

/// What the "Tick habit" shortcut needs, from the cached projection only
/// (it may run offline): the habits that can be ticked, and the tick for
/// today's training day.
public enum HabitQuickTick {
    public struct Choice: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let icon: String?
    }

    public enum Outcome: Equatable, Sendable {
        /// Record this; `label` is the habit's name.
        case tick(HabitTickPayload, label: String)
        /// The plan doesn't expect the habit today.
        case notPlannedToday(label: String)
        case unknownHabit
    }

    /// The ladder's active habits, in step order.
    public static func choices(projection: Projection?, language: TrainingLanguage) -> [Choice] {
        (projection?.habits.ladder ?? [])
            .filter { $0.state?.known == .active }
            .map { Choice(id: $0.id, label: $0.label.resolvedText(language) ?? $0.id, icon: $0.icon) }
    }

    /// "Done" for `habitID` on today's training day.
    public static func tick(habitID: String, projection: Projection?, language: TrainingLanguage, now: Date, deviceTimeZone: TimeZone) -> Outcome {
        guard let projection, let habit = projection.habits.habit(habitID) else { return .unknownHabit }
        let label = habit.label.resolvedText(language) ?? habit.id
        let date = CheckInPlanning.trainingDay(now: now, athlete: projection.athlete, deviceTimeZone: deviceTimeZone)
        let day = projection.plan.flatMap { EffectivePlan(plan: $0).day(date) }
        guard day?.habitsExpected.contains(habitID) == true else { return .notPlannedToday(label: label) }
        return .tick(HabitTickPayload(date: date, habitId: habitID, done: true), label: label)
    }
}
