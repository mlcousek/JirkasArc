// CheckInOverlay.swift
//
// The optimistic half of the check-ins (add-training-checkins design D5;
// the architecture note's section 4.4): the phone's own recent events,
// folded into "latest wins" state, so a check-in, a habit tick, an RPE or
// a note shows the moment it is recorded -- long before the vault has
// ingested it and published a new projection.
//
//   - latest wins per key: the light per training day, a tick per (day,
//     habit), an RPE and a note per session. "Latest" is the recording
//     time, then `seq` (a device's own order; a new device id starts at 1
//     again, but always later);
//   - each value says whether it is only saved on the phone, sent (its
//     segment is no longer pending in VaultKit's write queue) or received
//     (the projection's `acks[deviceId].seq` has reached its `seq`: the
//     vault read every event of this device up to it -- the contract's
//     rule for clearing a pending event);
//   - it wins over the projection's value for the same key while the event
//     is kept (TrainingEventLog, 21 days). The vault ingests the very same
//     events, so both then agree; `acks` in the projection are reserved in
//     v1 and not read yet.
//
// The phone never runs the vault's traffic-light rules: an amber check-in
// shows amber, and the week adapts at the next desk sync.
//
// `EffectivePlan` applies `lights` to each day's `light`, so every builder
// (Today's highlight, the month glyph, the detail's pre-selection) shows
// the phone's check-in without a builder change.
//
// add-checkin-pain-score D3: the morning pain follows the vault's
// replace/keep rule -- per day, the `pains` of the latest check-in of that
// date that CARRIES them (non-nil). A later check-in without `pains` (a
// corrected light, a lock-screen Control) keeps the earlier answer; one
// with `pains`, `[]` included, replaces it. `applyingLights` also sets the
// day's `pains` from it.
//
// add-interactive-habits: the vault refuses a `habit.tick` for a future day
// or one more than 14 days back and says so in the projection's `outcomes`
// (`type: "habit.tick"`, `status: "refused"`, a bilingual reason). Such a
// tick changed nothing in the vault, so it is NOT laid over the plan: it is
// kept in `refusedHabitTicks` with its reason for the habit's screen, and
// an earlier accepted tick of the same day stays what the day shows.
// add-daily-checkin-and-pain-mode: the same replacement runs over the day
// skeletons (`applying(to:)` on a list of days), so a check-in on a day
// outside every written week -- or with no plan at all -- shows too.
// `unconfirmedPainDates` is the phone's half of pain mode (PainModeState).
//
// add-training-gates-and-load (its design D3): four more facts ride the
// same fold, each "latest wins" like the vault folds them --
//   - `gateTests`: the last gate test per date;
//   - `sessionPains`: per session the `pains` of the last rating that
//     CARRIES them (a later RPE without them keeps the answer, like the
//     morning pain);
//   - `manualDone`: per session the last `session.done` this phone has
//     not retracted, with its event id (the undo names it);
//   - `fuelLogs` per session and `raceResults` per race, the last not
//     retracted; a race result the vault refused (a `race.result` outcome)
//     carries its reason.
// A retracted fact leaves the fold (same device, a later `seq`), as it
// leaves the vault's. A session done by hand is laid over the plan like a
// check-in light, but only WHILE THE VAULT HAS NOT READ IT: an
// unacknowledged `session.done` turns a session the file does not show as
// done (and not skipped) into `done` with `source: manual`; an
// unacknowledged retraction turns a session the file shows as done by
// that very event back into `planned`. Once acknowledged, the projection
// alone decides -- a completion the vault did not count never stays on
// screen. The week's sums are never touched: `actual` is the vault's.
//
// Plan commands (add-plan-editing) are not folded here: they are
// PendingOverlay's (PlanCommandOverlay.swift).
//
// Depended on by: TrainingSnapshot/EffectivePlan, the builders,
// TrainingReminderPlanner. Tests: CheckInOverlayTests.

import Foundation

public enum EventDelivery: Equatable, Sendable {
    case savedOnPhone
    case sent
    /// The vault acknowledged it (`acks[deviceId].seq >= seq`).
    case received
}

public struct OverlayValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let delivery: EventDelivery

    public init(value: Value, delivery: EventDelivery) {
        self.value = value
        self.delivery = delivery
    }
}

public struct HabitDayKey: Hashable, Sendable {
    public let date: LocalDate
    public let habitId: String

    public init(date: LocalDate, habitId: String) {
        self.date = date
        self.habitId = habitId
    }
}

/// add-interactive-habits: a tick of this phone the vault refused.
public struct HabitTickRefusal: Equatable, Sendable {
    /// The vault's reason (`{ en, cz }`); `nil` when it gave none.
    public let reason: LocalizedText?

    public init(reason: LocalizedText?) {
        self.reason = reason
    }
}

/// add-training-gates-and-load: a fact of this phone with the id of the
/// event that said it (an undo retracts that id).
public struct OverlayRecord<Value: Equatable & Sendable>: Equatable, Sendable {
    public let eventID: String
    public let value: Value
    public let delivery: EventDelivery

    public init(eventID: String, value: Value, delivery: EventDelivery) {
        self.eventID = eventID
        self.value = value
        self.delivery = delivery
    }
}

/// add-training-gates-and-load: this phone's last result for a race, and
/// the vault's refusal of it when there is one.
public struct RaceResultRecord: Equatable, Sendable {
    public let eventID: String
    public let payload: RaceResultPayload
    public let delivery: EventDelivery
    public let isRefused: Bool
    /// The vault's reason (`{ en, cz }`); `nil` when it gave none.
    public let refusalReason: LocalizedText?

    public init(eventID: String, payload: RaceResultPayload, delivery: EventDelivery, isRefused: Bool = false, refusalReason: LocalizedText? = nil) {
        self.eventID = eventID
        self.payload = payload
        self.delivery = delivery
        self.isRefused = isRefused
        self.refusalReason = refusalReason
    }
}

public struct CheckInOverlay: Equatable, Sendable {
    public static let empty = CheckInOverlay()

    public private(set) var lights: [LocalDate: OverlayValue<MorningLight>] = [:]
    /// The session a check-in named, per day (kept with the light).
    public private(set) var checkInSessions: [LocalDate: String] = [:]
    public private(set) var habitTicks: [HabitDayKey: OverlayValue<Bool>] = [:]
    public private(set) var rpes: [String: OverlayValue<Int>] = [:]
    public private(set) var notes: [String: OverlayValue<String>] = [:]
    /// add-checkin-pain-score: the day's answer, from the latest check-in
    /// of that date that carried `pains` (see this file's header).
    public private(set) var painAnswers: [LocalDate: OverlayValue<[PainEntry]>] = [:]
    /// add-interactive-habits: the phone's ticks the vault refused (see
    /// this file's header). Never in `habitTicks`.
    public private(set) var refusedHabitTicks: [HabitDayKey: HabitTickRefusal] = [:]
    /// add-training-gates-and-load (see this file's header).
    public private(set) var gateTests: [LocalDate: OverlayValue<GateTestPayload>] = [:]
    public private(set) var sessionPains: [String: OverlayValue<[SessionPainEntry]>] = [:]
    public private(set) var manualDone: [String: OverlayRecord<SessionDonePayload>] = [:]
    /// Retracted `session.done` events: lowercased event id -> the
    /// retraction's delivery.
    public private(set) var retractedDone: [String: EventDelivery] = [:]
    public private(set) var fuelLogs: [String: OverlayRecord<SessionFuelPayload>] = [:]
    public private(set) var raceResults: [String: RaceResultRecord] = [:]

    public init() {}

    public var isEmpty: Bool {
        lights.isEmpty && habitTicks.isEmpty && rpes.isEmpty && notes.isEmpty && painAnswers.isEmpty
            && gateTests.isEmpty && sessionPains.isEmpty && manualDone.isEmpty && retractedDone.isEmpty
            && fuelLogs.isEmpty && raceResults.isEmpty
    }

    /// The phone's gate test of `date`.
    public func gateTest(on date: LocalDate) -> OverlayValue<GateTestPayload>? {
        gateTests[date]
    }

    /// The phone's newest gate test (by its date).
    public var latestGateTest: OverlayValue<GateTestPayload>? {
        gateTests.max { $0.key < $1.key }?.value
    }

    /// The phone's pain during / after for session `id`.
    public func pains(session id: String) -> OverlayValue<[SessionPainEntry]>? {
        sessionPains[id]
    }

    /// The phone's "done without a watch" for session `id`, not retracted.
    public func doneByHand(session id: String) -> OverlayRecord<SessionDonePayload>? {
        manualDone[id]
    }

    public func fuelLog(session id: String) -> OverlayRecord<SessionFuelPayload>? {
        fuelLogs[id]
    }

    public func raceResult(race id: String) -> RaceResultRecord? {
        raceResults[id]
    }

    public func light(on date: LocalDate) -> OverlayValue<MorningLight>? {
        lights[date]
    }

    /// The phone's pain answer for `date`; `nil` when no check-in of the
    /// phone carried one.
    public func pains(on date: LocalDate) -> OverlayValue<[PainEntry]>? {
        painAnswers[date]
    }

    public func habitTick(on date: LocalDate, habitId: String) -> OverlayValue<Bool>? {
        habitTicks[HabitDayKey(date: date, habitId: habitId)]
    }

    /// add-interactive-habits: the vault's refusal of the phone's latest
    /// tick for that day; `nil` when it was not refused.
    public func refusedHabitTick(on date: LocalDate, habitId: String) -> HabitTickRefusal? {
        refusedHabitTicks[HabitDayKey(date: date, habitId: habitId)]
    }

    public func rpe(session id: String) -> OverlayValue<Int>? {
        rpes[id]
    }

    public func note(session id: String) -> OverlayValue<String>? {
        notes[id]
    }

    /// The projection's `acks` as `deviceId -> seq` (the highest `n` with
    /// events `1...n` all received). Anything unreadable is left out.
    public static func ackedSeqs(from acks: [String: JSONValue]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (device, value) in acks {
            guard case .object(let fields) = value, case .number(let seq)? = fields["seq"], seq >= 0 else { continue }
            result[device] = Int(seq)
        }
        return result
    }

    /// Folds `events`; `unsentSegments` are the segment ids still pending
    /// (or failed) in the write queue; `ackedSeqs` from `ackedSeqs(from:)`;
    /// `outcomes` from `PlanOutcome.parse` -- only the refused habit ticks
    /// are read here (add-interactive-habits).
    public static func fold(_ events: [LoggedEvent], unsentSegments: Set<UUID>, ackedSeqs: [String: Int] = [:], outcomes: [PlanOutcome] = []) -> CheckInOverlay {
        var overlay = CheckInOverlay()
        let refusals = outcomes.filter { outcome in
            outcome.status.known == .refused && (outcome.type == nil || outcome.type == HubEventType.habitTick.rawValue)
        }
        let raceRefusals = outcomes.filter { outcome in
            outcome.status.known == .refused && outcome.type == HubEventType.raceResult.rawValue
        }
        let ordered = events.sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
            return lhs.event.seq < rhs.event.seq
        }
        func deliveryOf(_ logged: LoggedEvent) -> EventDelivery {
            if let acked = ackedSeqs[logged.event.deviceId], logged.event.seq <= acked {
                return .received
            }
            if let segment = logged.segmentID, !unsentSegments.contains(segment) {
                return .sent
            }
            return .savedOnPhone
        }
        // add-training-gates-and-load: retractions by their target's id.
        var retractions: [String: LoggedEvent] = [:]
        for logged in ordered {
            if case .eventRetracted(let payload) = logged.event.payload {
                retractions[payload.target.lowercased()] = logged
            }
        }
        /// The delivery of the retraction that took `logged` out of the
        /// fold (same device, a later `seq`); `nil` when it is still in.
        func retraction(of logged: LoggedEvent) -> EventDelivery? {
            guard let found = retractions[logged.event.id.lowercased()],
                  found.event.deviceId == logged.event.deviceId,
                  found.event.seq > logged.event.seq
            else { return nil }
            return deliveryOf(found)
        }
        for logged in ordered {
            let delivery = deliveryOf(logged)
            switch logged.event.payload {
            case .morningCheckIn(let payload):
                overlay.lights[payload.date] = OverlayValue(value: payload.light, delivery: delivery)
                overlay.checkInSessions[payload.date] = payload.sessionId
                // Keep without the key, replace with it (`[]` included).
                if let pains = payload.pains {
                    overlay.painAnswers[payload.date] = OverlayValue(value: pains, delivery: delivery)
                }
            case .habitTick(let payload):
                let key = HabitDayKey(date: payload.date, habitId: payload.habitId)
                // add-interactive-habits: a refused tick changed nothing in
                // the vault; an accepted one after it clears the refusal.
                let event = logged.event
                let refusal = refusals.first { outcome in
                    if let id = outcome.event { return id.lowercased() == event.id.lowercased() }
                    return outcome.deviceId == event.deviceId && outcome.seq == event.seq
                }
                if let refusal {
                    overlay.refusedHabitTicks[key] = HabitTickRefusal(reason: refusal.reason)
                } else {
                    overlay.habitTicks[key] = OverlayValue(value: payload.done, delivery: delivery)
                    overlay.refusedHabitTicks[key] = nil
                }
            case .sessionRPE(let payload):
                overlay.rpes[payload.sessionId] = OverlayValue(value: payload.rpe, delivery: delivery)
                // Keep without the key, replace with it (`[]` included).
                if let pains = payload.pains {
                    overlay.sessionPains[payload.sessionId] = OverlayValue(value: pains, delivery: delivery)
                }
            case .testGate(let payload):
                if retraction(of: logged) != nil { continue }
                overlay.gateTests[payload.date] = OverlayValue(value: payload, delivery: delivery)
            case .sessionDone(let payload):
                if let undone = retraction(of: logged) {
                    overlay.retractedDone[logged.event.id.lowercased()] = undone
                    continue
                }
                overlay.manualDone[payload.sessionId] = OverlayRecord(eventID: logged.event.id, value: payload, delivery: delivery)
            case .sessionFuel(let payload):
                if retraction(of: logged) != nil { continue }
                overlay.fuelLogs[payload.sessionId] = OverlayRecord(eventID: logged.event.id, value: payload, delivery: delivery)
            case .raceResult(let payload):
                if retraction(of: logged) != nil { continue }
                let event = logged.event
                let refusal = raceRefusals.first { outcome in
                    if let id = outcome.event { return id.lowercased() == event.id.lowercased() }
                    return outcome.deviceId == event.deviceId && outcome.seq == event.seq
                }
                overlay.raceResults[payload.raceId] = RaceResultRecord(
                    eventID: event.id,
                    payload: payload,
                    delivery: delivery,
                    isRefused: refusal != nil,
                    refusalReason: refusal?.reason
                )
            case .sessionNote(let payload):
                overlay.notes[payload.sessionId] = OverlayValue(value: payload.text, delivery: delivery)
            case .sessionMoved, .sessionsSwapped, .sessionSkipped, .sessionUnskipped, .ruleOverridden, .eventRetracted:
                // Plan commands: PendingOverlay's (add-plan-editing). A
                // retraction of a fact was read above (`retractions`).
                continue
            case .other:
                continue
            }
        }
        return overlay
    }

    /// `plan` with each day's `light` replaced by the phone's check-in, and
    /// its `pains` by the phone's pain answer (add-checkin-pain-score).
    public func applyingLights(to plan: Plan) -> Plan {
        guard hasDayOverlay else { return plan }
        var result = plan
        for weekIndex in result.weeks.indices {
            result.weeks[weekIndex].days = applying(to: result.weeks[weekIndex].days)
        }
        return result
    }

    /// `days` with the phone's check-in light and pain answer on each
    /// (plan-week days and day skeletons alike).
    public func applying(to days: [Day]) -> [Day] {
        guard hasDayOverlay else { return days }
        var result = days
        for index in result.indices {
            let date = result[index].date
            if let local = lights[date] {
                result[index].light = OpenEnum(local.value)
                result[index].lightSource = OpenEnum(LightSource.checkin)
            }
            if let local = painAnswers[date] {
                result[index].pains = local.value
            }
            guard !manualDone.isEmpty || !retractedDone.isEmpty else { continue }
            for sessionIndex in result[index].sessions.indices {
                result[index].sessions[sessionIndex] = applyingManualDone(to: result[index].sessions[sessionIndex])
            }
        }
        return result
    }

    /// Whether anything of the phone's is laid over a day.
    private var hasDayOverlay: Bool {
        !lights.isEmpty || !painAnswers.isEmpty || !manualDone.isEmpty || !retractedDone.isEmpty
    }

    /// add-training-gates-and-load D3: the phone's unacknowledged "done
    /// without a watch" (and its unacknowledged undo) over one session.
    func applyingManualDone(to session: Session) -> Session {
        var result = session
        let status = session.status?.known
        if let local = manualDone[session.id], local.delivery != .received,
           status != .done, status != .skipped, session.done == nil {
            // The option counts only when the session has it (the vault's
            // rule for `done.option`).
            var option: OpenEnum<OptionCode>?
            if let code = local.value.option, session.option(code) != nil {
                option = OpenEnum<OptionCode>(code)
            }
            result.status = OpenEnum(SessionStatus.done)
            result.done = Done(
                option: option,
                source: OpenEnum(DoneSource.manual),
                matchedBy: OpenEnum(MatchedBy.manual),
                activity: nil,
                manual: ManualDone(
                    date: local.value.date,
                    option: local.value.option.map { OpenEnum<OptionCode>($0) },
                    min: local.value.min,
                    km: local.value.km,
                    note: local.value.note,
                    event: local.eventID
                )
            )
            return result
        }
        if let done = session.done, done.isManual, done.activity == nil,
           let event = done.manual?.event?.lowercased(),
           let undo = retractedDone[event], undo != .received {
            result.status = OpenEnum(SessionStatus.planned)
            result.done = nil
        }
        return result
    }

    /// The days whose pain answer on this phone has a score above 0 and
    /// that the vault has not read yet: not acknowledged (`received`), and
    /// not the answer the projection itself shows for the day
    /// (`vaultPains`, the file's own `day.pains`). Oldest first.
    public func unconfirmedPainDates(vaultPains: [LocalDate: [PainEntry]]) -> [LocalDate] {
        var dates: [LocalDate] = []
        for (date, answer) in painAnswers {
            guard answer.value.contains(where: { $0.score > 0 }) else { continue }
            if answer.delivery == .received { continue }
            if let vault = vaultPains[date], vault == answer.value { continue }
            dates.append(date)
        }
        return dates.sorted { $0 < $1 }
    }
}
