// HubEvent.swift
//
// THE wire format of what the app writes to the vault (add-training-checkins
// design D2): one event per training action, serialised as one JSON object
// per line (JSONL) into segment files under `events/<deviceId>/`. This is
// the ONLY file that knows the envelope's field names, the type strings and
// the payload keys. It follows the vault's event contract v1 (its
// `add-hub-ingest` change, "Event log v1" in its Training Hub Contract),
// whose two fixtures are mirrored verbatim under
// Tests/TrainingCoreTests/Fixtures/Contract/vault/ and decoded by
// `HubEventTests`, beside the app's own golden files
// (Fixtures/Events/events.v1.app.jsonl and plan-commands.v1.app.jsonl,
// byte-exact).
//
//   {"at":"2030-10-23T04:07:31.000+02:00","deviceId":"ios-0000beef",
//    "id":"<UUIDv7>","payload":{...},"seq":7,"type":"checkin.morning","v":1}
//
//   checkin.morning  {date, light: green|amber|red, sessionId?, option?: G|A|R,
//                     pains?: [{site, score, note?}]}   (add-checkin-pain-score)
//   habit.tick       {date, habitId, done}           (decision A42: on/off)
//   session.rpe      {date, sessionId, rpe: 1...10, feel?: 1...5}
//   session.note     {date, sessionId, text}         (1...2000 characters)
//
// add-plan-editing adds the plan commands and the retraction (its design
// D2). Commands carry the ISO week and the week revision the app showed,
// never a `date`:
//
//   plan.session.moved      {week, baseRevision, sessionId, from, to}
//   plan.session.swapped    {week, baseRevision, a, aDate, b, bDate}
//   plan.session.skipped    {week, baseRevision, sessionId, reason?}
//   plan.session.unskipped  {week, baseRevision, sessionId}
//   plan.rule.overridden    {week, baseRevision, sessionId, rule}
//   event.retracted         {target, reason?}
//
// The contract: optional keys may be absent or `null` with the same
// meaning, and the app should write them -- so this encoder writes them,
// as `null` when unknown. The light is the morning's state, never the
// workout letter; `option` is the option he intends (the light's letter
// when the day has a traffic-light session, else null). `pains` (the
// vault's A57, add-checkin-pain-score D1) is null when the pain was not
// asked -- the vault then keeps the day's earlier answer -- and a list,
// possibly empty, when it was (Pain.swift has the entry's shape). The
// vault's `device.hello` decodes as `.other` here: this app doesn't write
// it yet.
//
// add-training-gates-and-load adds the vault's facts of 2026-10-01 and
// 2026-10-05 (its design D1):
//
//   test.gate     {date, walkPain, hopPain, site?, note?}
//   session.done  {date, sessionId, option?, min?, km?, note?}
//   session.fuel  {date, sessionId, carbsG, fluidMl?, durationMin?, note?}
//   race.result   {raceId, status: finished|dnf|dns, reason?, time?,
//                  officialTime?, distanceKm?, laps?, note?}   (no `date`)
//   session.rpe   gains pains?: [{site, during?, after?}]
//
// Optional keys are written as `null` like everywhere else -- with THREE
// exceptions, each one where the vault's own example line leaves the key
// out, so this app's line is the same JSON object as the vault's:
//   - `officialTime` is left out unless the owner filled it (the contract:
//     "omit it for a race with one time, never send a copy of `time`");
//   - `pains` on `session.rpe` is left out when the pain was not asked (a
//     tap on an RPE number alone) -- the vault keeps the session's earlier
//     answer either way, and every rating recorded before this change
//     keeps its bytes;
//   - `during` / `after` of one site are left out when that score was not
//     asked.
// Numbers that can carry a fraction go through `WireNumber`: a whole value
// is written as an integer (`4`, `10`), anything else as an exact decimal
// (`1.5`, `42.2`), so the bytes never depend on how a platform prints a
// double. The app's byte-exact golden file for them is
// Fixtures/Events/gates.v1.app.jsonl -- the vault example's own six lines
// (seq 25-28, 32, 33) as this app encodes them: key-sorted, nothing else
// changed.
//
// Encoding is deterministic (sorted keys, unescaped slashes, `\n` after
// every line) because a sealed segment's bytes and git blob SHA must be the
// same on every retry (VaultKit's SealedFile). `.sortedKeys` compares keys
// case-sensitively (by code unit) on Apple platforms, so `bDate` precedes
// `baseRevision` in a swap; the golden fixtures record the exact bytes.
// Decoding is tolerant: unknown fields are ignored and an unknown type is
// kept as `.other`, never encoded.
//
// Depended on by: TrainingEventLog (stores these), EventSegment (writes
// them), CheckInOverlay and PendingOverlay (fold them), PlanEditPolicy
// (builds the commands), the record models (SessionRecordModels,
// GateModels, RaceResultModels), TrainingRecorder. Tests: HubEventTests.

import Foundation

// MARK: - Types and payloads

public enum HubEventType: Hashable, Sendable {
    case morningCheckIn
    case habitTick
    case sessionRPE
    case sessionNote
    case sessionMoved
    case sessionsSwapped
    case sessionSkipped
    case sessionUnskipped
    case ruleOverridden
    case eventRetracted
    /// add-training-gates-and-load.
    case testGate
    case sessionDone
    case sessionFuel
    case raceResult
    /// A type this build doesn't write (read from a newer fixture).
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "test.gate": self = .testGate
        case "session.done": self = .sessionDone
        case "session.fuel": self = .sessionFuel
        case "race.result": self = .raceResult
        case "checkin.morning": self = .morningCheckIn
        case "habit.tick": self = .habitTick
        case "session.rpe": self = .sessionRPE
        case "session.note": self = .sessionNote
        case "plan.session.moved": self = .sessionMoved
        case "plan.session.swapped": self = .sessionsSwapped
        case "plan.session.skipped": self = .sessionSkipped
        case "plan.session.unskipped": self = .sessionUnskipped
        case "plan.rule.overridden": self = .ruleOverridden
        case "event.retracted": self = .eventRetracted
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .morningCheckIn: return "checkin.morning"
        case .habitTick: return "habit.tick"
        case .sessionRPE: return "session.rpe"
        case .sessionNote: return "session.note"
        case .sessionMoved: return "plan.session.moved"
        case .sessionsSwapped: return "plan.session.swapped"
        case .sessionSkipped: return "plan.session.skipped"
        case .sessionUnskipped: return "plan.session.unskipped"
        case .ruleOverridden: return "plan.rule.overridden"
        case .eventRetracted: return "event.retracted"
        case .testGate: return "test.gate"
        case .sessionDone: return "session.done"
        case .sessionFuel: return "session.fuel"
        case .raceResult: return "race.result"
        case .other(let raw): return raw
        }
    }
}

public struct MorningCheckInPayload: Equatable, Sendable {
    /// The training day the check-in is for.
    public var date: LocalDate
    public var light: MorningLight
    /// The day's traffic-light session, when it has one.
    public var sessionId: String?
    /// The option he intends: by default the light's letter when there is
    /// a session, else `nil` (the contract's `option?`).
    public var option: OptionCode?
    /// add-checkin-pain-score: `nil` = pain not asked (the vault keeps the
    /// day's earlier answer), `[]` = asked, nothing hurts.
    public var pains: [PainEntry]?

    public init(date: LocalDate, light: MorningLight, sessionId: String? = nil, pains: [PainEntry]? = nil) {
        self.init(date: date, light: light, sessionId: sessionId, option: sessionId == nil ? nil : light.option, pains: pains)
    }

    public init(date: LocalDate, light: MorningLight, sessionId: String?, option: OptionCode?, pains: [PainEntry]? = nil) {
        self.date = date
        self.light = light
        self.sessionId = sessionId
        self.option = option
        self.pains = pains
    }
}

public struct HabitTickPayload: Equatable, Sendable {
    public var date: LocalDate
    public var habitId: String
    public var done: Bool

    public init(date: LocalDate, habitId: String, done: Bool) {
        self.date = date
        self.habitId = habitId
        self.done = done
    }
}

public struct SessionRPEPayload: Equatable, Sendable {
    public static let range = 1...10
    public static let feelRange = 1...5

    public var date: LocalDate
    public var sessionId: String
    public var rpe: Int
    /// The contract's optional 1-5 feel; the app doesn't ask for it yet
    /// (tasks 0.5) and writes `null`.
    public var feel: Int?
    /// add-training-gates-and-load: pain during / after the session.
    /// `nil` = not asked (the key is left out and the vault keeps the
    /// session's earlier answer), `[]` = asked, nothing hurt.
    public var pains: [SessionPainEntry]?

    public init(date: LocalDate, sessionId: String, rpe: Int, feel: Int? = nil, pains: [SessionPainEntry]? = nil) {
        self.date = date
        self.sessionId = sessionId
        self.rpe = rpe
        self.feel = feel
        self.pains = pains
    }
}

// MARK: Facts of add-training-gates-and-load

/// The weekly gate test: pain when walking and on 20 single-leg hops.
/// One per date (the last sent wins); the vault judges it.
public struct GateTestPayload: Equatable, Sendable {
    public var date: LocalDate
    /// 0...10 in steps of 0.5.
    public var walkPain: Double
    /// 0...10 in steps of 0.5.
    public var hopPain: Double
    /// The tested site; `nil` leaves the vault's default.
    public var site: PainSite?
    /// 1-200 UTF-16 units.
    public var note: String?

    public init(date: LocalDate, walkPain: Double, hopPain: Double, site: PainSite? = nil, note: String? = nil) {
        self.date = date
        self.walkPain = walkPain
        self.hopPain = hopPain
        self.site = site
        self.note = note
    }
}

/// "Done without a watch": the session counts as done when no activity
/// matched; a synced activity replaces it.
public struct SessionDonePayload: Equatable, Sendable {
    public static let minutesRange = 1...6000
    public static let maxKm = 1000.0

    public var date: LocalDate
    public var sessionId: String
    /// The option actually done, when the session has options.
    public var option: OptionCode?
    public var min: Int?
    /// Above 0; written on a grid of 0.01 km.
    public var km: Double?
    public var note: String?

    public init(date: LocalDate, sessionId: String, option: OptionCode? = nil, min: Int? = nil, km: Double? = nil, note: String? = nil) {
        self.date = date
        self.sessionId = sessionId
        self.option = option
        self.min = min
        self.km = km
        self.note = note
    }
}

/// What was eaten during a session. `carbsG: 0` is an answer.
public struct SessionFuelPayload: Equatable, Sendable {
    public static let carbsRange: ClosedRange<Double> = 0...2000
    public static let maxFluidMl = 50_000

    public var date: LocalDate
    public var sessionId: String
    /// Grams of carbohydrate; written on a grid of 0.1 g.
    public var carbsG: Double
    public var fluidMl: Int?
    /// How long the session really took, when the app knows.
    public var durationMin: Int?
    public var note: String?

    public init(date: LocalDate, sessionId: String, carbsG: Double, fluidMl: Int? = nil, durationMin: Int? = nil, note: String? = nil) {
        self.date = date
        self.sessionId = sessionId
        self.carbsG = carbsG
        self.fluidMl = fluidMl
        self.durationMin = durationMin
        self.note = note
    }
}

/// How a race ended. It carries no `date`: the race's date is the plan's.
public struct RaceResultPayload: Equatable, Sendable {
    public static let maxDistanceKm = 10_000.0
    public static let maxLaps = 100_000

    public var raceId: String
    public var status: RaceOutcome
    /// With `dnf` / `dns`.
    public var reason: RaceResultReason?
    /// The ELAPSED time, `h:mm:ss`.
    public var time: String?
    /// The organiser's results time when it is another one; `nil` is left
    /// out of the event.
    public var officialTime: String?
    public var distanceKm: Double?
    public var laps: Int?
    public var note: String?

    public init(
        raceId: String,
        status: RaceOutcome,
        reason: RaceResultReason? = nil,
        time: String? = nil,
        officialTime: String? = nil,
        distanceKm: Double? = nil,
        laps: Int? = nil,
        note: String? = nil
    ) {
        self.raceId = raceId
        self.status = status
        self.reason = reason
        self.time = time
        self.officialTime = officialTime
        self.distanceKm = distanceKm
        self.laps = laps
        self.note = note
    }

    /// `h:mm:ss`: hours without a leading zero ("0:46:03", "21:31:23");
    /// "3h24" and "3:24" are not times.
    public static func isValidTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        let allDigits = parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard allDigits else { return false }
        let hours = parts[0]
        guard hours.count <= 3, hours.count == 1 || hours.first != "0" else { return false }
        guard parts[1].count == 2, parts[2].count == 2,
              let minutes = Int(parts[1]), let seconds = Int(parts[2]),
              minutes < 60, seconds < 60
        else { return false }
        return true
    }
}

/// A number on the wire (add-training-gates-and-load D1): `value` rounded
/// to a grid of 1/`steps`, written as an integer when whole (`4`, not
/// `4.0`) and as an exact decimal otherwise (`1.5`, `42.2`) -- a
/// `Decimal`, which every Foundation prints digit for digit, never a
/// binary double. `nil` is written as `null` by `encode` and left out by
/// `encodeIfPresent`.
enum WireNumber {
    /// Like `encode`, but a `nil` leaves the key out.
    static func encodeIfPresent<Key: CodingKey>(_ value: Double?, steps: Int, into container: inout KeyedEncodingContainer<Key>, forKey key: Key) throws {
        guard let value else { return }
        try encode(value, steps: steps, into: &container, forKey: key)
    }

    static func encode<Key: CodingKey>(_ value: Double?, steps: Int, into container: inout KeyedEncodingContainer<Key>, forKey key: Key) throws {
        guard let value, value.isFinite, steps >= 1 else {
            try container.encodeNil(forKey: key)
            return
        }
        let scaled = (value * Double(steps)).rounded()
        guard abs(scaled) < 1e12 else {
            try container.encode(value, forKey: key)
            return
        }
        let units = Int(scaled)
        if units % steps == 0 {
            try container.encode(units / steps, forKey: key)
        } else {
            try container.encode(Decimal(units) / Decimal(steps), forKey: key)
        }
    }

    /// `value` on the grid of 1/`steps` (what `encode` writes).
    static func rounded(_ value: Double, steps: Int) -> Double {
        (value * Double(steps)).rounded() / Double(steps)
    }
}

public struct SessionNotePayload: Equatable, Sendable {
    public static let maxLength = 2000

    public var date: LocalDate
    public var sessionId: String
    public var text: String

    public init(date: LocalDate, sessionId: String, text: String) {
        self.date = date
        self.sessionId = sessionId
        self.text = text
    }
}

// MARK: Plan commands (add-plan-editing D2)

/// Move a session to another day of the same ISO week.
public struct SessionMovedPayload: Equatable, Sendable {
    public var week: ISOWeek
    /// The `week.revision` the app showed.
    public var baseRevision: Int
    public var sessionId: String
    public var from: LocalDate
    public var to: LocalDate

    public init(week: ISOWeek, baseRevision: Int, sessionId: String, from: LocalDate, to: LocalDate) {
        self.week = week
        self.baseRevision = baseRevision
        self.sessionId = sessionId
        self.from = from
        self.to = to
    }
}

/// Swap the dates of two sessions of one week.
public struct SessionsSwappedPayload: Equatable, Sendable {
    public var week: ISOWeek
    public var baseRevision: Int
    public var a: String
    public var aDate: LocalDate
    public var b: String
    public var bDate: LocalDate

    public init(week: ISOWeek, baseRevision: Int, a: String, aDate: LocalDate, b: String, bDate: LocalDate) {
        self.week = week
        self.baseRevision = baseRevision
        self.a = a
        self.aDate = aDate
        self.b = b
        self.bDate = bDate
    }
}

public struct SessionSkippedPayload: Equatable, Sendable {
    public var week: ISOWeek
    public var baseRevision: Int
    public var sessionId: String
    /// Optional, 1-2000 characters (the contract's text limit).
    public var reason: String?

    public init(week: ISOWeek, baseRevision: Int, sessionId: String, reason: String? = nil) {
        self.week = week
        self.baseRevision = baseRevision
        self.sessionId = sessionId
        self.reason = reason
    }
}

public struct SessionUnskippedPayload: Equatable, Sendable {
    public var week: ISOWeek
    public var baseRevision: Int
    public var sessionId: String

    public init(week: ISOWeek, baseRevision: Int, sessionId: String) {
        self.week = week
        self.baseRevision = baseRevision
        self.sessionId = sessionId
    }
}

/// Decision A17: the human overrides a rule's edit of one session.
public struct RuleOverriddenPayload: Equatable, Sendable {
    public var week: ISOWeek
    public var baseRevision: Int
    public var sessionId: String
    /// The rule id (`two-ambers`).
    public var rule: String

    public init(week: ISOWeek, baseRevision: Int, sessionId: String, rule: String) {
        self.week = week
        self.baseRevision = baseRevision
        self.sessionId = sessionId
        self.rule = rule
    }
}

/// Takes an earlier event of the same device out of the vault's fold.
public struct EventRetractedPayload: Equatable, Sendable {
    /// The retracted event's id.
    public var target: String
    public var reason: String?

    public init(target: String, reason: String? = nil) {
        self.target = target
        self.reason = reason
    }
}

public enum HubEventPayload: Equatable, Sendable {
    case morningCheckIn(MorningCheckInPayload)
    case habitTick(HabitTickPayload)
    case sessionRPE(SessionRPEPayload)
    case sessionNote(SessionNotePayload)
    case sessionMoved(SessionMovedPayload)
    case sessionsSwapped(SessionsSwappedPayload)
    case sessionSkipped(SessionSkippedPayload)
    case sessionUnskipped(SessionUnskippedPayload)
    case ruleOverridden(RuleOverriddenPayload)
    case eventRetracted(EventRetractedPayload)
    case testGate(GateTestPayload)
    case sessionDone(SessionDonePayload)
    case sessionFuel(SessionFuelPayload)
    case raceResult(RaceResultPayload)
    /// An unknown type, read only; `date` when its payload had one.
    case other(type: String, date: LocalDate?)

    public var type: HubEventType {
        switch self {
        case .testGate: return .testGate
        case .sessionDone: return .sessionDone
        case .sessionFuel: return .sessionFuel
        case .raceResult: return .raceResult
        case .morningCheckIn: return .morningCheckIn
        case .habitTick: return .habitTick
        case .sessionRPE: return .sessionRPE
        case .sessionNote: return .sessionNote
        case .sessionMoved: return .sessionMoved
        case .sessionsSwapped: return .sessionsSwapped
        case .sessionSkipped: return .sessionSkipped
        case .sessionUnskipped: return .sessionUnskipped
        case .ruleOverridden: return .ruleOverridden
        case .eventRetracted: return .eventRetracted
        case .other(let type, _): return .other(type)
        }
    }

    /// The training day of a fact; `nil` for the commands (they carry a
    /// week), a retraction and a race result (it names its race).
    public var date: LocalDate? {
        switch self {
        case .testGate(let payload): return payload.date
        case .sessionDone(let payload): return payload.date
        case .sessionFuel(let payload): return payload.date
        case .raceResult: return nil
        case .morningCheckIn(let payload): return payload.date
        case .habitTick(let payload): return payload.date
        case .sessionRPE(let payload): return payload.date
        case .sessionNote(let payload): return payload.date
        case .sessionMoved, .sessionsSwapped, .sessionSkipped, .sessionUnskipped, .ruleOverridden, .eventRetracted:
            return nil
        case .other(_, let date): return date
        }
    }

    /// The ISO week of a plan command; `nil` for everything else.
    public var commandWeek: ISOWeek? {
        switch self {
        case .sessionMoved(let payload): return payload.week
        case .sessionsSwapped(let payload): return payload.week
        case .sessionSkipped(let payload): return payload.week
        case .sessionUnskipped(let payload): return payload.week
        case .ruleOverridden(let payload): return payload.week
        default: return nil
        }
    }

    /// Whether this is a `plan.*` command.
    public var isPlanCommand: Bool { commandWeek != nil }

    /// The sessions a plan command names (two for a swap).
    public var commandSessionIDs: [String] {
        switch self {
        case .sessionMoved(let payload): return [payload.sessionId]
        case .sessionsSwapped(let payload): return [payload.a, payload.b]
        case .sessionSkipped(let payload): return [payload.sessionId]
        case .sessionUnskipped(let payload): return [payload.sessionId]
        case .ruleOverridden(let payload): return [payload.sessionId]
        default: return []
        }
    }

    /// Whether this build may write it (see `HubEventError`).
    public func validate() throws {
        switch self {
        case .morningCheckIn(let payload):
            for pain in payload.pains ?? [] {
                if !PainEntry.isValidScore(pain.score) { throw HubEventError.invalidPayload("pain score must be 0-10 in steps of 0.5") }
                if !PainEntry.isValidNote(pain.note) { throw HubEventError.invalidPayload("pain note must be 1-200 characters") }
            }
        case .habitTick(let payload):
            if payload.habitId.isEmpty { throw HubEventError.invalidPayload("empty habitId") }
        case .sessionRPE(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if !SessionRPEPayload.range.contains(payload.rpe) { throw HubEventError.invalidPayload("rpe out of range") }
            if let feel = payload.feel, !SessionRPEPayload.feelRange.contains(feel) { throw HubEventError.invalidPayload("feel out of range") }
            for pain in payload.pains ?? [] where !pain.isValid {
                throw HubEventError.invalidPayload("session pain must be 0-10 in steps of 0.5")
            }
        case .testGate(let payload):
            if !PainEntry.isValidScore(payload.walkPain) || !PainEntry.isValidScore(payload.hopPain) {
                throw HubEventError.invalidPayload("gate score must be 0-10 in steps of 0.5")
            }
            if !PainEntry.isValidNote(payload.note) { throw HubEventError.invalidPayload("gate note must be 1-200 characters") }
        case .sessionDone(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if let minutes = payload.min, !SessionDonePayload.minutesRange.contains(minutes) { throw HubEventError.invalidPayload("minutes out of range") }
            if let km = payload.km, !(km.isFinite && km > 0 && km <= SessionDonePayload.maxKm) { throw HubEventError.invalidPayload("km out of range") }
            try Self.validateText(payload.note)
        case .sessionFuel(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if !(payload.carbsG.isFinite && SessionFuelPayload.carbsRange.contains(payload.carbsG)) { throw HubEventError.invalidPayload("carbs out of range") }
            if let fluid = payload.fluidMl, !(0...SessionFuelPayload.maxFluidMl).contains(fluid) { throw HubEventError.invalidPayload("fluid out of range") }
            if let minutes = payload.durationMin, !SessionDonePayload.minutesRange.contains(minutes) { throw HubEventError.invalidPayload("duration out of range") }
            try Self.validateText(payload.note)
        case .raceResult(let payload):
            if payload.raceId.isEmpty { throw HubEventError.invalidPayload("empty raceId") }
            if let time = payload.time, !RaceResultPayload.isValidTime(time) { throw HubEventError.invalidPayload("time is not h:mm:ss") }
            if let official = payload.officialTime {
                if !RaceResultPayload.isValidTime(official) { throw HubEventError.invalidPayload("official time is not h:mm:ss") }
                if official == payload.time { throw HubEventError.invalidPayload("official time is a copy of the elapsed time") }
            }
            if let km = payload.distanceKm, !(km.isFinite && km > 0 && km <= RaceResultPayload.maxDistanceKm) { throw HubEventError.invalidPayload("distance out of range") }
            if let laps = payload.laps, !(0...RaceResultPayload.maxLaps).contains(laps) { throw HubEventError.invalidPayload("laps out of range") }
            try Self.validateText(payload.note)
        case .sessionNote(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if payload.text.isEmpty { throw HubEventError.invalidPayload("empty note") }
            if payload.text.count > SessionNotePayload.maxLength { throw HubEventError.invalidPayload("note too long") }
        case .sessionMoved(let payload):
            try Self.validateCommand(payload.baseRevision, ids: [payload.sessionId])
            if payload.from == payload.to { throw HubEventError.invalidPayload("move to the same day") }
            if !payload.week.contains(payload.from) || !payload.week.contains(payload.to) {
                throw HubEventError.invalidPayload("move outside its week")
            }
        case .sessionsSwapped(let payload):
            try Self.validateCommand(payload.baseRevision, ids: [payload.a, payload.b])
            if payload.a == payload.b { throw HubEventError.invalidPayload("swap with itself") }
            if payload.aDate == payload.bDate { throw HubEventError.invalidPayload("swap on the same day") }
            if !payload.week.contains(payload.aDate) || !payload.week.contains(payload.bDate) {
                throw HubEventError.invalidPayload("swap outside its week")
            }
        case .sessionSkipped(let payload):
            try Self.validateCommand(payload.baseRevision, ids: [payload.sessionId])
            try Self.validateText(payload.reason)
        case .sessionUnskipped(let payload):
            try Self.validateCommand(payload.baseRevision, ids: [payload.sessionId])
        case .ruleOverridden(let payload):
            try Self.validateCommand(payload.baseRevision, ids: [payload.sessionId])
            if payload.rule.isEmpty { throw HubEventError.invalidPayload("empty rule") }
        case .eventRetracted(let payload):
            if payload.target.isEmpty { throw HubEventError.invalidPayload("empty target") }
            try Self.validateText(payload.reason)
        case .other:
            throw HubEventError.unknownType
        }
    }

    private static func validateCommand(_ baseRevision: Int, ids: [String]) throws {
        if baseRevision < 1 { throw HubEventError.invalidPayload("baseRevision below 1") }
        if ids.contains(where: { $0.isEmpty }) { throw HubEventError.invalidPayload("empty sessionId") }
    }

    /// An optional text: absent, or 1-2000 characters.
    private static func validateText(_ text: String?) throws {
        guard let text else { return }
        if text.isEmpty { throw HubEventError.invalidPayload("empty text") }
        if text.count > SessionNotePayload.maxLength { throw HubEventError.invalidPayload("text too long") }
    }
}

public enum HubEventError: Error, Equatable, Sendable {
    case invalidPayload(String)
    /// `.other` events are read, never written.
    case unknownType
}

// MARK: - Envelope

public struct HubEvent: Equatable, Sendable, Identifiable {
    public static let envelopeVersion = 1

    public let v: Int
    /// UUIDv7, lowercase (`UUIDv7.string`); the vault dedupes by it.
    public let id: String
    /// `ios-xxxxxxxx`, the folder the event is written into.
    public let deviceId: String
    /// Per device, monotonic, never reused.
    public let seq: Int
    /// Producer wall clock with its UTC offset (`HubEventClock`).
    public let at: String
    public let payload: HubEventPayload

    public var type: HubEventType { payload.type }

    public init(v: Int = HubEvent.envelopeVersion, id: String, deviceId: String, seq: Int, at: String, payload: HubEventPayload) {
        self.v = v
        self.id = id
        self.deviceId = deviceId
        self.seq = seq
        self.at = at
        self.payload = payload
    }
}

extension HubEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case v, id, deviceId, seq, at, type, payload
    }

    enum PayloadKeys: String, CodingKey {
        case date, light, sessionId, option, pains, habitId, done, rpe, feel, text
        case week, baseRevision, from, to, a, aDate, b, bDate, reason, rule, target
        // add-training-gates-and-load.
        case walkPain, hopPain, site, note, min, km
        case carbsG, fluidMl, durationMin
        case raceId, status, time, officialTime, distanceKm, laps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? HubEvent.envelopeVersion
        id = try c.decode(String.self, forKey: .id)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        seq = try c.decode(Int.self, forKey: .seq)
        at = try c.decode(String.self, forKey: .at)
        let type = HubEventType(rawValue: try c.decode(String.self, forKey: .type))

        if case .other(let raw) = type {
            let p = try? c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
            let dateText = (try? p?.decodeIfPresent(String.self, forKey: .date)) ?? nil
            payload = .other(type: raw, date: dateText.flatMap { LocalDate($0) })
            return
        }

        let p = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        if let command = try Self.decodeCommand(type, p) {
            payload = command
            return
        }
        let dateText = try p.decode(String.self, forKey: .date)
        guard let date = LocalDate(dateText) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: p, debugDescription: "not a YYYY-MM-DD date")
        }
        switch type {
        case .morningCheckIn:
            let lightText = try p.decode(String.self, forKey: .light)
            guard let light = MorningLight(rawValue: lightText) else {
                throw DecodingError.dataCorruptedError(forKey: .light, in: p, debugDescription: "unknown light")
            }
            let optionText = try p.decodeIfPresent(String.self, forKey: .option)
            payload = .morningCheckIn(MorningCheckInPayload(
                date: date,
                light: light,
                sessionId: try p.decodeIfPresent(String.self, forKey: .sessionId),
                option: optionText.flatMap { OptionCode(rawValue: $0) },
                // Absent or null = not asked; an unknown site is `other`.
                pains: try p.decodeIfPresent([PainEntry].self, forKey: .pains)
            ))
        case .habitTick:
            payload = .habitTick(HabitTickPayload(
                date: date,
                habitId: try p.decode(String.self, forKey: .habitId),
                done: try p.decode(Bool.self, forKey: .done)
            ))
        case .sessionRPE:
            payload = .sessionRPE(SessionRPEPayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                rpe: try p.decode(Int.self, forKey: .rpe),
                feel: try p.decodeIfPresent(Int.self, forKey: .feel),
                // Absent or null = not asked; an unknown site is `other`.
                pains: try p.decodeIfPresent([SessionPainEntry].self, forKey: .pains)
            ))
        case .testGate:
            payload = .testGate(GateTestPayload(
                date: date,
                walkPain: try p.decode(Double.self, forKey: .walkPain),
                hopPain: try p.decode(Double.self, forKey: .hopPain),
                site: try p.decodeIfPresent(String.self, forKey: .site).map { PainSite(wire: $0) },
                note: try p.decodeIfPresent(String.self, forKey: .note)
            ))
        case .sessionDone:
            let optionText = try p.decodeIfPresent(String.self, forKey: .option)
            payload = .sessionDone(SessionDonePayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                option: optionText.flatMap { OptionCode(rawValue: $0) },
                min: try p.decodeIfPresent(Int.self, forKey: .min),
                km: try p.decodeIfPresent(Double.self, forKey: .km),
                note: try p.decodeIfPresent(String.self, forKey: .note)
            ))
        case .sessionFuel:
            payload = .sessionFuel(SessionFuelPayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                carbsG: try p.decode(Double.self, forKey: .carbsG),
                fluidMl: try p.decodeIfPresent(Int.self, forKey: .fluidMl),
                durationMin: try p.decodeIfPresent(Int.self, forKey: .durationMin),
                note: try p.decodeIfPresent(String.self, forKey: .note)
            ))
        case .sessionNote:
            payload = .sessionNote(SessionNotePayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                text: try p.decode(String.self, forKey: .text)
            ))
        case .other(let raw):
            payload = .other(type: raw, date: date)
        case .sessionMoved, .sessionsSwapped, .sessionSkipped, .sessionUnskipped, .ruleOverridden, .eventRetracted, .raceResult:
            // Already returned by `decodeCommand`.
            throw DecodingError.dataCorruptedError(forKey: .date, in: p, debugDescription: "a command has no date")
        }
    }

    /// The commands, the retraction and the race result (they have no
    /// `date`); `nil` for the dated facts.
    private static func decodeCommand(_ type: HubEventType, _ p: KeyedDecodingContainer<PayloadKeys>) throws -> HubEventPayload? {
        func week() throws -> ISOWeek {
            let raw = try p.decode(String.self, forKey: .week)
            guard let week = ISOWeek(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .week, in: p, debugDescription: "not a YYYY-Www week")
            }
            return week
        }
        func day(_ key: PayloadKeys) throws -> LocalDate {
            let raw = try p.decode(String.self, forKey: key)
            guard let date = LocalDate(raw) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: p, debugDescription: "not a YYYY-MM-DD date")
            }
            return date
        }
        switch type {
        case .sessionMoved:
            return .sessionMoved(SessionMovedPayload(
                week: try week(),
                baseRevision: try p.decode(Int.self, forKey: .baseRevision),
                sessionId: try p.decode(String.self, forKey: .sessionId),
                from: try day(.from),
                to: try day(.to)
            ))
        case .sessionsSwapped:
            return .sessionsSwapped(SessionsSwappedPayload(
                week: try week(),
                baseRevision: try p.decode(Int.self, forKey: .baseRevision),
                a: try p.decode(String.self, forKey: .a),
                aDate: try day(.aDate),
                b: try p.decode(String.self, forKey: .b),
                bDate: try day(.bDate)
            ))
        case .sessionSkipped:
            return .sessionSkipped(SessionSkippedPayload(
                week: try week(),
                baseRevision: try p.decode(Int.self, forKey: .baseRevision),
                sessionId: try p.decode(String.self, forKey: .sessionId),
                reason: try p.decodeIfPresent(String.self, forKey: .reason)
            ))
        case .sessionUnskipped:
            return .sessionUnskipped(SessionUnskippedPayload(
                week: try week(),
                baseRevision: try p.decode(Int.self, forKey: .baseRevision),
                sessionId: try p.decode(String.self, forKey: .sessionId)
            ))
        case .ruleOverridden:
            return .ruleOverridden(RuleOverriddenPayload(
                week: try week(),
                baseRevision: try p.decode(Int.self, forKey: .baseRevision),
                sessionId: try p.decode(String.self, forKey: .sessionId),
                rule: try p.decode(String.self, forKey: .rule)
            ))
        case .eventRetracted:
            return .eventRetracted(EventRetractedPayload(
                target: try p.decode(String.self, forKey: .target),
                reason: try p.decodeIfPresent(String.self, forKey: .reason)
            ))
        case .raceResult:
            // An unknown status decides nothing: the line is invalid (the
            // vault rejects such an event too). An unknown reason is
            // `other`, like the vault reads it.
            let statusText = try p.decode(String.self, forKey: .status)
            guard let status = RaceOutcome(rawValue: statusText) else {
                throw DecodingError.dataCorruptedError(forKey: .status, in: p, debugDescription: "unknown race status")
            }
            let reasonText = try p.decodeIfPresent(String.self, forKey: .reason)
            return .raceResult(RaceResultPayload(
                raceId: try p.decode(String.self, forKey: .raceId),
                status: status,
                reason: reasonText.map { RaceResultReason(rawValue: $0) ?? .other },
                time: try p.decodeIfPresent(String.self, forKey: .time),
                officialTime: try p.decodeIfPresent(String.self, forKey: .officialTime),
                distanceKm: try p.decodeIfPresent(Double.self, forKey: .distanceKm),
                laps: try p.decodeIfPresent(Int.self, forKey: .laps),
                note: try p.decodeIfPresent(String.self, forKey: .note)
            ))
        case .morningCheckIn, .habitTick, .sessionRPE, .sessionNote, .testGate, .sessionDone, .sessionFuel, .other:
            return nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .other = payload {
            throw EncodingError.invalidValue(type.rawValue, EncodingError.Context(codingPath: [], debugDescription: "unknown event types are never written"))
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(seq, forKey: .seq)
        try c.encode(at, forKey: .at)
        try c.encode(type.rawValue, forKey: .type)
        var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        switch payload {
        case .morningCheckIn(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.light.rawValue, forKey: .light)
            // Optional keys are written, as null when unknown (contract).
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.option?.rawValue, forKey: .option)
            try p.encode(value.pains, forKey: .pains)
        case .habitTick(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.habitId, forKey: .habitId)
            try p.encode(value.done, forKey: .done)
        case .sessionRPE(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.rpe, forKey: .rpe)
            try p.encode(value.feel, forKey: .feel)
            // Left out when the pain was not asked (this file's header).
            if let pains = value.pains {
                try p.encode(pains, forKey: .pains)
            }
        case .testGate(let value):
            try p.encode(value.date.description, forKey: .date)
            try WireNumber.encode(value.walkPain, steps: 2, into: &p, forKey: .walkPain)
            try WireNumber.encode(value.hopPain, steps: 2, into: &p, forKey: .hopPain)
            try p.encode(value.site?.rawValue, forKey: .site)
            try p.encode(value.note, forKey: .note)
        case .sessionDone(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.option?.rawValue, forKey: .option)
            try p.encode(value.min, forKey: .min)
            try WireNumber.encode(value.km, steps: 100, into: &p, forKey: .km)
            try p.encode(value.note, forKey: .note)
        case .sessionFuel(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try WireNumber.encode(value.carbsG, steps: 10, into: &p, forKey: .carbsG)
            try p.encode(value.fluidMl, forKey: .fluidMl)
            try p.encode(value.durationMin, forKey: .durationMin)
            try p.encode(value.note, forKey: .note)
        case .raceResult(let value):
            try p.encode(value.raceId, forKey: .raceId)
            try p.encode(value.status.rawValue, forKey: .status)
            try p.encode(value.reason?.rawValue, forKey: .reason)
            try p.encode(value.time, forKey: .time)
            // The one optional key that is left out when unknown (see this
            // file's header): a race with one time has no `officialTime`.
            if let official = value.officialTime {
                try p.encode(official, forKey: .officialTime)
            }
            try WireNumber.encode(value.distanceKm, steps: 100, into: &p, forKey: .distanceKm)
            try p.encode(value.laps, forKey: .laps)
            try p.encode(value.note, forKey: .note)
        case .sessionNote(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.text, forKey: .text)
        case .sessionMoved(let value):
            try p.encode(value.week.description, forKey: .week)
            try p.encode(value.baseRevision, forKey: .baseRevision)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.from.description, forKey: .from)
            try p.encode(value.to.description, forKey: .to)
        case .sessionsSwapped(let value):
            try p.encode(value.week.description, forKey: .week)
            try p.encode(value.baseRevision, forKey: .baseRevision)
            try p.encode(value.a, forKey: .a)
            try p.encode(value.aDate.description, forKey: .aDate)
            try p.encode(value.b, forKey: .b)
            try p.encode(value.bDate.description, forKey: .bDate)
        case .sessionSkipped(let value):
            try p.encode(value.week.description, forKey: .week)
            try p.encode(value.baseRevision, forKey: .baseRevision)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.reason, forKey: .reason)
        case .sessionUnskipped(let value):
            try p.encode(value.week.description, forKey: .week)
            try p.encode(value.baseRevision, forKey: .baseRevision)
            try p.encode(value.sessionId, forKey: .sessionId)
        case .ruleOverridden(let value):
            try p.encode(value.week.description, forKey: .week)
            try p.encode(value.baseRevision, forKey: .baseRevision)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.rule, forKey: .rule)
        case .eventRetracted(let value):
            try p.encode(value.target, forKey: .target)
            try p.encode(value.reason, forKey: .reason)
        case .other:
            break
        }
    }
}

// MARK: - JSONL

public enum HubEventCodec {
    /// Sorted keys and unescaped slashes: the same event is always the same
    /// bytes (see this file's header).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// One event as one line, without the newline.
    public static func line(_ event: HubEvent) throws -> Data {
        try makeEncoder().encode(event)
    }

    /// Events as JSONL: every line followed by `\n`.
    public static func jsonl(_ events: [HubEvent]) throws -> Data {
        var data = Data()
        for event in events {
            data.append(try line(event))
            data.append(0x0A)
        }
        return data
    }

    public struct DecodedLines: Equatable, Sendable {
        public var events: [HubEvent] = []
        /// 1-based numbers of the lines that did not decode.
        public var invalidLines: [Int] = []
    }

    /// Reads JSONL tolerantly: blank lines are skipped, a `\r` before the
    /// `\n` is ignored, and a line that doesn't decode is reported, not
    /// fatal.
    public static func decode(_ data: Data) -> DecodedLines {
        var result = DecodedLines()
        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            var line = Data(rawLine)
            if line.last == 0x0D { line.removeLast() }
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { continue }
            do {
                result.events.append(try decoder.decode(HubEvent.self, from: line))
            } catch {
                result.invalidLines.append(index + 1)
            }
        }
        return result
    }
}

// MARK: - Clock

public enum HubEventClock {
    /// `2030-10-23T04:07:31.000+02:00`: local wall clock, milliseconds, the
    /// zone's offset at that instant (`Z` for UTC).
    public static func string(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter.string(from: date)
    }
}

// MARK: - Lights, options

public extension MorningLight {
    /// The check-in's order on screen and in the Controls: G, A, R.
    static let checkInOrder: [MorningLight] = [.greenLight, .amberLight, .redLight]
}
