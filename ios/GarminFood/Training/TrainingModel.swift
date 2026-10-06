// TrainingModel.swift
//
// The plan as Today and Plan read it (add-training-today-and-plan task 4.1,
// design D12): a thin `@MainActor @Observable` holder of TrainingCore's
// `TrainingSource` -- still fetching, not published, unreadable, or a
// loaded `TrainingSnapshot` with its freshness. Every rule (decoding, the
// last good copy, freshness, the training day, what each card shows) lives
// in TrainingCore and is tested there; this only gathers the inputs and
// hands out builders in the app's language.
//
// Inputs: the last good projection (`ProjectionStore`, decoded off the main
// actor, no network), the refused-file reason, and VaultKit's status (the
// last successful sync, a 404 on the file). A rejection is remembered
// across launches in UserDefaults while VaultKit still holds a refused
// ETag -- the store keeps it in memory only, and after a relaunch the same
// refused file answers 304, so without this the loud "Update Jirka's Arc"
// would vanish while the file is still too new.
//
// Rebuilt: at launch and every foreground (AppEnvironment), after each
// projection refresh and disconnect (VaultController.onProjectionRefresh),
// and on day change. Views re-run the builders on each render; they are
// cheap and pure.
//
// add-training-checkins: it also carries the phone's own events
// (TrainingEventsService's overlay) and what the app may record
// (`TrainingCapabilities.checkIns(enabled:)`: connection on and a device
// id) into the snapshot, turns taps into events (check-in, habit tick, RPE,
// note -- local, durable, never waiting for the network), and re-plans the
// training reminders after each change.
//
// add-plan-editing: it also carries the phone's plan commands
// (`PendingOverlay`, folded with the cached projection's `acks` and
// `outcomes`) into the snapshot, with `TrainingCapabilities.recording`
// turning plan edits on under the same guard, and turns Move, Swap, Skip,
// Undo the skip, Override the rule and Withdraw into commands built by
// TrainingCore's PlanEditPolicy (which refuses what the vault would
// refuse) and recorded like a check-in.
//
// add-checkin-pain-score: the pain step's Save records the row's check-in
// again with `pains` (`recordPain`), which replaces the day's answer; a
// light alone keeps it (TrainingCore's CheckInOverlay).
//
// add-interactive-habits: it hands out `HabitsBuilder` (streaks, history,
// the day controls) and turns a control's step into what TrainingCore's
// `HabitDosePolicy` says: the on/off tick through the same recorder, and
// -- for a multi-dose day that isn't complete -- a count kept on the phone
// (`habitDoses`, one preference value; the wire only carries on/off, A42).
// add-daily-checkin-and-pain-mode: the two reminder times are the owner's
// (UserDefaults, like the food reminders' times; 04:05 and 20:10 until
// changed), and `isPainMode` tells the app whether the pain features show
// (TrainingCore's `PainModeState`: the vault's word, or this phone's own
// unread pain answer).
//
// add-training-gates-and-load: five more facts go through the same
// recorder -- the weekly gate test, pain during and after a session (with
// the RPE), "done without a watch", the fuel log and a race result -- and
// their undo is a retraction per event. Every payload is built by a
// TrainingCore model (bounds checked there); nothing is recorded unless the
// vault connection can record, and nothing waits for the network.
//
// improve-food-day-flow: the evening habits reminder also mentions a food
// log that is not closed. The closed days come from the food side through
// `closedFoodDaysProvider` (set by AppEnvironment+FoodDayFlow); the wording
// is TrainingCore's (`TrainingReminderPlanner`).
//
// Owned by AppEnvironment (`environment.training`); read by the Today
// training cards, the Plan tab and the Habits screens.

import Foundation
import Observation
import TrainingCore
import VaultKit
import GarminKit

@MainActor
@Observable
final class TrainingModel {
    static let rejectionKey = "training.projection.rejection.v1"

    private(set) var source: TrainingSource = .waitingForFirstSync
    private(set) var hasLoaded = false
    /// add-training-checkins: the last recording error, for an alert.
    var actionError: String?
    /// The app's language (Settings -> Language), fixed for the process.
    let language: TrainingLanguage
    /// add-interactive-habits: doses done so far on multi-dose days that
    /// are not complete yet (the phone's own note; see the header).
    private(set) var habitDoses: HabitDoseLedger = .empty

    @ObservationIgnored private let store: ProjectionStore
    @ObservationIgnored private let vault: VaultController
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var didRestoreRejection = false
    @ObservationIgnored private let events: TrainingEventsService
    /// The replan in flight; the next one waits for it (`syncReminders`).
    @ObservationIgnored private var reminderSync: Task<Void, Never>? = nil
    /// improve-food-day-flow: the days whose food log is closed, for the
    /// evening reminder's wording. `nil` (not set, or it answers `nil`) =
    /// the food log is not mentioned at all.
    @ObservationIgnored var closedFoodDaysProvider: (@MainActor () -> Set<LocalDate>?)? = nil

    /// add-training-checkins D8: the training reminders switch (default on,
    /// tasks 0.2).
    static let remindersKey = "training.reminders.enabled.v1"
    /// add-interactive-habits: `habitDoses`, as JSON.
    static let habitDosesKey = "training.habitDoses.v1"
    /// add-daily-checkin-and-pain-mode: when the two reminders fire.
    static let checkInHourKey = "training.reminders.checkin.hour.v1"
    static let checkInMinuteKey = "training.reminders.checkin.minute.v1"
    static let habitsHourKey = "training.reminders.habits.hour.v1"
    static let habitsMinuteKey = "training.reminders.habits.minute.v1"

    init(store: ProjectionStore, vault: VaultController, events: TrainingEventsService, defaults: UserDefaults = .standard) {
        self.store = store
        self.vault = vault
        self.events = events
        self.defaults = defaults
        self.language = TrainingLanguage.from(preferredLocalizations: Bundle.main.preferredLocalizations)
        self.habitDoses = HabitDoseLedger(encoded: defaults.data(forKey: Self.habitDosesKey))
        events.onChange = { [weak self] in
            await self?.reload()
        }
    }

    // MARK: Recording (add-training-checkins)

    /// The morning check-in for `date` (Today's row).
    func checkIn(_ light: MorningLight, date: LocalDate, sessionID: String?) async {
        await perform(.morningCheckIn(MorningCheckInPayload(date: date, light: light, sessionId: sessionID)))
    }

    /// add-checkin-pain-score: the check-in with the morning pain, built by
    /// TrainingCore's `PainStepModel.payload` (same light, session and
    /// option as the row).
    func recordPain(_ payload: MorningCheckInPayload) async {
        await perform(.morningCheckIn(payload))
    }

    /// Habit on/off for `date` (decision A42).
    func setHabit(_ habitID: String, done: Bool, date: LocalDate) async {
        await perform(.habitTick(HabitTickPayload(date: date, habitId: habitID, done: done)))
    }

    /// add-interactive-habits: one step of a day's control (Today's card,
    /// the Habits screens, a back-filled day) to `target` doses. Below the
    /// day's doses only the phone's count changes; completing the day, or
    /// taking it back, records the tick. Local, never waits.
    func applyHabit(_ control: HabitDayControlModel, to target: Int) async {
        guard control.canRecord else { return }
        let change = control.change(to: target)
        var doses = habitDoses
        doses.set(change.partial, on: control.date, habitID: control.habitID)
        storeHabitDoses(doses)
        if let done = change.tick {
            await setHabit(control.habitID, done: done, date: control.date)
        }
    }

    private func storeHabitDoses(_ doses: HabitDoseLedger) {
        guard doses != habitDoses else { return }
        habitDoses = doses
        if doses.isEmpty {
            defaults.removeObject(forKey: Self.habitDosesKey)
        } else {
            defaults.set(doses.encoded, forKey: Self.habitDosesKey)
        }
    }

    func rate(sessionID: String, date: LocalDate, rpe: Int) async {
        await perform(.sessionRPE(SessionRPEPayload(date: date, sessionId: sessionID, rpe: rpe)))
    }

    func saveNote(sessionID: String, date: LocalDate, text: String) async {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SessionNotePayload.maxLength))
        await perform(.sessionNote(SessionNotePayload(date: date, sessionId: sessionID, text: trimmed)))
    }

    // MARK: Gates, load and results (add-training-gates-and-load)

    /// The weekly gate test (`GateCardModel.payload`); the vault judges it.
    func recordGateTest(_ payload: GateTestPayload) async {
        await perform(.testGate(payload))
    }

    /// Pain during and after a session: the same RPE again with `pains`
    /// (`SessionPainModel.payload`).
    func recordSessionPain(_ payload: SessionRPEPayload) async {
        await perform(.sessionRPE(payload))
    }

    /// "Mark done (no watch)" (`ManualDoneModel.payload`). Shown as done at
    /// once; the vault counts it at the next sync.
    func markDone(_ payload: SessionDonePayload) async {
        Haptics.success()
        await perform(.sessionDone(payload))
    }

    /// The fuel log of a long run or a race (`SessionFuelModel.payload`).
    func logFuel(_ payload: SessionFuelPayload) async {
        await perform(.sessionFuel(payload))
    }

    /// How a race ended (`RaceResultEditorModel.payload`).
    func recordRaceResult(_ payload: RaceResultPayload) async {
        await perform(.raceResult(payload))
    }

    /// Undo of "done without a watch" and Withdraw of a race result: one
    /// retraction per event of this phone that still stands (the vault
    /// takes the last one that is not retracted).
    func retractEvents(_ eventIDs: [String]) async {
        for id in eventIDs {
            await perform(.eventRetracted(EventRetractedPayload(target: id)))
        }
    }

    /// Records locally (durable), then the service schedules delivery and
    /// calls back into `reload`. A failure is shown, never swallowed.
    private func perform(_ payload: HubEventPayload) async {
        do {
            try await events.record(payload)
        } catch {
            DiagnosticsLog.log(.error, category: "training", "recording \(payload.type.rawValue) failed: \(error)")
            actionError = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't save that on the phone. Try again.", comment: "Training: recording a check-in, tick, RPE or note failed.")
        }
    }

    // MARK: Plan edits (add-plan-editing D3, D6)

    func moveSession(_ sessionID: String, to date: LocalDate) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.move(sessionID: sessionID, to: date, snapshot: snapshot, today: today)
        }
    }

    func swapSession(_ sessionID: String, with partnerID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.swap(sessionID: sessionID, with: partnerID, snapshot: snapshot, today: today)
        }
    }

    func skipSession(_ sessionID: String, reason: String?) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.skip(sessionID: sessionID, reason: reason, snapshot: snapshot, today: today)
        }
    }

    func unskipSession(_ sessionID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.unskip(sessionID: sessionID, snapshot: snapshot, today: today)
        }
    }

    /// Decision A17: called only after the warning was confirmed.
    func overrideRule(_ rule: String, sessionID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.overrideRule(rule, sessionID: sessionID, snapshot: snapshot, today: today)
        }
    }

    /// Retracts this phone's pending command (or applied override).
    func withdrawPlanChange(_ commandID: String) async {
        await performEdit { snapshot, _ in
            try PlanEditPolicy.withdraw(commandID: commandID, snapshot: snapshot)
        }
    }

    /// Builds the command from the current snapshot and training day, then
    /// records it like any other event. A refusal means the plan changed
    /// under the screen; it is said, never swallowed.
    private func performEdit(_ make: (TrainingSnapshot, LocalDate) throws -> HubEventPayload) async {
        guard let snapshot = source.snapshot else { return }
        let payload: HubEventPayload
        do {
            payload = try make(snapshot, today())
        } catch {
            DiagnosticsLog.log(.error, category: "training", "plan edit not offered any more: \(error)")
            actionError = String(localized: "That change isn't possible any more: the plan has changed. Have another look.", comment: "add-plan-editing: a plan change was refused on the phone because the plan changed under the screen.")
            return
        }
        Haptics.success()
        await perform(payload)
    }

    // MARK: Reminders (add-training-checkins D8)

    var remindersEnabled: Bool {
        defaults.object(forKey: Self.remindersKey) as? Bool ?? true
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Self.remindersKey)
        await syncReminders()
    }

    /// add-daily-checkin-and-pain-mode: when the check-in and the habits
    /// reminders fire (04:05 and 20:10 until the owner changes them).
    var reminderTimes: TrainingReminderTimes {
        let standard = TrainingReminderTimes.standard
        return TrainingReminderTimes(
            morningHour: defaults.object(forKey: Self.checkInHourKey) as? Int ?? standard.morningHour,
            morningMinute: defaults.object(forKey: Self.checkInMinuteKey) as? Int ?? standard.morningMinute,
            eveningHour: defaults.object(forKey: Self.habitsHourKey) as? Int ?? standard.eveningHour,
            eveningMinute: defaults.object(forKey: Self.habitsMinuteKey) as? Int ?? standard.eveningMinute
        )
    }

    func setReminderTimes(_ times: TrainingReminderTimes) async {
        defaults.set(times.morningHour, forKey: Self.checkInHourKey)
        defaults.set(times.morningMinute, forKey: Self.checkInMinuteKey)
        defaults.set(times.eveningHour, forKey: Self.habitsHourKey)
        defaults.set(times.eveningMinute, forKey: Self.habitsMinuteKey)
        // The scheduler's identifiers carry the fire time, so the replan
        // removes the requests at the old time and adds the new ones.
        await syncReminders()
    }

    /// add-daily-checkin-and-pain-mode: whether the pain features show.
    var isPainMode: Bool {
        source.snapshot?.painMode.isActive ?? false
    }

    /// Re-plans the training reminders from the current snapshot; none when
    /// the switch is off or the connection can't record. One replan at a
    /// time (add-daily-checkin-and-pain-mode): a time picker reports every
    /// step of its wheel, and two replans interleaving around the
    /// scheduler's awaits could leave requests at both times pending.
    func syncReminders(now: Date = Date()) async {
        let previous = reminderSync
        let task = Task<Void, Never> { [weak self] in
            _ = await previous?.value
            await self?.replanReminders(now: now)
        }
        reminderSync = task
        await task.value
    }

    private func replanReminders(now: Date) async {
        let allowed = remindersEnabled && events.isConnectionOn()
        let reminders = allowed
            // fix-review-findings-2026-09 finding 11: a week ahead, from the
            // cached projection (the same 7 days as the food reminders,
            // NotificationPlanning.windowDays), so reminders outlive a
            // closed app.
            ? TrainingReminderPlanner.plan(
                snapshot: source.snapshot,
                today: today(now: now),
                now: now,
                timeZone: .current,
                language: language,
                days: 7,
                times: reminderTimes,
                closedFoodDays: closedFoodDaysProvider?()
            )
            : []
        await NotificationScheduler.shared.syncTrainingReminders(reminders, now: now)
    }

    // MARK: Days

    private var athlete: Athlete {
        source.snapshot?.athlete ?? Athlete()
    }

    /// The current training day (athlete.tz and day boundary, D6).
    func today(now: Date = Date()) -> LocalDate {
        TrainingDay.current(now: now, boundaryHour: athlete.dayBoundaryHour, timeZone: athlete.timeZone(fallback: .current))
    }

    /// The plan day for the day switcher's selection (Today follows it).
    func trainingDay(selectedDate: Date, isToday: Bool, now: Date = Date()) -> LocalDate {
        TrainingDay.resolve(
            selectedDate: LocalDate(date: selectedDate, timeZone: .current),
            isToday: isToday,
            now: now,
            athlete: athlete,
            deviceTimeZone: .current
        )
    }

    // MARK: Builders

    /// add-training-gates-and-load: the builder knows the current training
    /// day, so what describes "now" (the gate test, the recovery window,
    /// the vault's notices) is not shown on a day being browsed.
    var todayBuilder: TodayTrainingBuilder {
        TodayTrainingBuilder(source: source, language: language, today: today())
    }

    func planBuilder(now: Date = Date()) -> PlanBuilder {
        PlanBuilder(source: source, language: language, today: today(now: now))
    }

    /// add-interactive-habits: the Habits screens and Today's checks.
    func habitsBuilder(now: Date = Date()) -> HabitsBuilder {
        HabitsBuilder(source: source, language: language, today: today(now: now), doses: habitDoses)
    }

    // MARK: Loading

    func reload(now: Date = Date()) async {
        if !didRestoreRejection {
            didRestoreRejection = true
            if let raw = defaults.string(forKey: Self.rejectionKey),
               let rejection = ProjectionRejection(reportReason: raw),
               await store.hasRejectedCopy() {
                await store.restoreRejection(rejection)
            }
        }
        let cached = await store.loadCached()
        let rejection = await store.rejection
        if let rejection {
            defaults.set(rejection.description, forKey: Self.rejectionKey)
        } else {
            defaults.removeObject(forKey: Self.rejectionKey)
        }

        let status = vault.status
        let availability = ProjectionAvailability.evaluate(
            cached: cached,
            rejection: rejection,
            fileNotFound: status.lastOutcome == .fileNotFound
        )
        let athlete = cached?.projection.athlete ?? Athlete()
        let trainingToday = TrainingDay.current(
            now: now,
            boundaryHour: athlete.dayBoundaryHour,
            timeZone: athlete.timeZone(fallback: .current)
        )
        let freshness = TrainingFreshness.evaluate(
            asOf: cached?.projection.asOf,
            trainingToday: trainingToday,
            lastSuccessAt: status.lastSuccessAt ?? cached?.fetchedAt,
            now: now,
            rejection: rejection,
            hasNewerVersionHint: cached?.projection.supersededBy != nil
        )
        // add-training-checkins: the phone's events over the plan, and
        // whether it may record at all.
        // (add-interactive-habits: `outcomes` name the habit ticks the vault
        // refused, so they are not shown as done.)
        let checkIns = await events.recorder.overlay(acks: cached?.projection.acks ?? [:], outcomes: cached?.projection.outcomes ?? [])
        // add-plan-editing: the phone's plan commands and the vault's
        // answers; plan edits under the same guard as the check-ins.
        let planEdits = await events.recorder.planEdits(acks: cached?.projection.acks ?? [:], outcomes: cached?.projection.outcomes ?? [])
        let canRecord = await events.canRecord()
        source = TrainingSource.from(availability, freshness: freshness, checkIns: checkIns, planEdits: planEdits, capabilities: .recording(enabled: canRecord))
        hasLoaded = true
        // add-interactive-habits: dose counts older than the event log
        // keeps its ticks are of no use to anything.
        var doses = habitDoses
        doses.prune(before: trainingToday.adding(days: -Int(TrainingEventLog.sealedRetention / 86_400)))
        storeHabitDoses(doses)
        await syncReminders(now: now)
    }
}
