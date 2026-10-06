// LoadAndResults.swift
//
// add-training-gates-and-load: the projection fields the vault added on
// 2026-10-01 (training load and gates) and 2026-10-05 (race results, the
// fuel log, the recovery window), additively within schema version 1. The
// vault COMPUTES every one of them; the phone only reads and shows them.
//
//   athlete.gate       the weekly gate test and the vault's verdict
//                      (`GateStatus`); `null` = never tested
//   athlete.recovery   the recovery window after a race (`RecoveryWindow`);
//                      `of` is 14 or 7 -- read it, never assume 14
//   notices[]          data gaps the app explains (`ProjectionNotice`)
//   done.manual        what was said when a session was ticked done by
//                      hand (`ManualDone`)
//   feedback.fuel      the fuel log with the vault's g/h (`FuelLog`)
//   races[].result     how a race ended (`RaceResult`): ONE source for the
//                      whole record, `time` is the elapsed time and
//                      `officialTime` the organiser's when that is another
//                      one (never a copy of `time`)
//
// Decoding follows Projection.swift's rules: identity is required (a gate
// needs its `date`, a recovery window its `day` and `of`, a notice its
// text), everything else is lenient, enumerations are open. A MISSING
// NUMBER IS UNKNOWN, NEVER 0, and the three-state Booleans (`runAllowed`,
// `goalReached`, `pr`, ...) stay `nil` when the vault did not say: `nil` is
// "not known", never "no".
//
// The session's pain during / after (`SessionPainEntry`) is in Pain.swift;
// the week's load fields are on `WeekActual` in Projection.swift.
//
// Depended on by: Projection (the slots), TrainingSnapshot, the gate, load,
// session-record and race-result view models. Tests:
// ProjectionDecodingTests, GatesAndLoadTests.

import Foundation

// MARK: - Enumerations

/// `unplanned[].flag`.
public enum ActivityFlag: String, OpenEnumValue {
    case overPlan = "over-plan"
}

/// `result.reason` and the event's `reason` (with `dnf` / `dns` only).
public enum RaceResultReason: String, OpenEnumValue {
    case stopRule = "stop-rule"
    case injury
    case illness
    case other
}

/// Where a race result came from: the race report, or the app's event.
public enum RaceResultSource: String, OpenEnumValue {
    case report
    case event
}

/// `feedback.fuel.vsPlan`: the vault's display band around the plan.
public enum FuelVsPlan: String, OpenEnumValue {
    case below
    case on
    case above
}

// MARK: - The gate test

/// `athlete.gate`: the last weekly gate test and what the vault makes of
/// it. `runAllowed` and `speedAllowed` are two separate facts; `nil` means
/// the vault did not say and is never read as "allowed".
public struct GateStatus: Equatable, Sendable, Decodable {
    public var date: LocalDate
    public var walkPain: Double?
    public var hopPain: Double?
    public var site: PainSite?
    public var runAllowed: Bool?
    public var speedAllowed: Bool?
    /// Weekly tests in a row with hops above 2/10, this one included.
    public var weeksHopAbove2: Int?
    /// The test is more than 14 days old at `asOf`: still shown, greyed.
    public var stale: Bool
    public var note: String?

    public init(
        date: LocalDate,
        walkPain: Double? = nil,
        hopPain: Double? = nil,
        site: PainSite? = nil,
        runAllowed: Bool? = nil,
        speedAllowed: Bool? = nil,
        weeksHopAbove2: Int? = nil,
        stale: Bool = false,
        note: String? = nil
    ) {
        self.date = date
        self.walkPain = walkPain
        self.hopPain = hopPain
        self.site = site
        self.runAllowed = runAllowed
        self.speedAllowed = speedAllowed
        self.weeksHopAbove2 = weeksHopAbove2
        self.stale = stale
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case date, walkPain, hopPain, site, runAllowed, speedAllowed, weeksHopAbove2, stale, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        walkPain = c.lenientDouble(.walkPain)
        hopPain = c.lenientDouble(.hopPain)
        site = c.lenientString(.site).map(PainSite.init(wire:))
        runAllowed = c.lenientBool(.runAllowed)
        speedAllowed = c.lenientBool(.speedAllowed)
        weeksHopAbove2 = c.lenientInt(.weeksHopAbove2).flatMap { $0 >= 0 ? $0 : nil }
        stale = c.lenientBool(.stale) ?? false
        note = c.lenientString(.note)
    }
}

// MARK: - The recovery window

/// `athlete.recovery`: day `day` of `of` after race `raceId`, until
/// `until`. Information only -- the app never blocks or edits a session on
/// it. `rule` is kept as written (an unknown one shows the day count only).
public struct RecoveryWindow: Equatable, Sendable, Decodable {
    public var raceId: String?
    public var day: Int
    /// 14, or 7 after a race that was not finished.
    public var of: Int
    public var rule: String?
    /// The last day of the window.
    public var until: LocalDate?

    public init(raceId: String? = nil, day: Int, of: Int, rule: String? = nil, until: LocalDate? = nil) {
        self.raceId = raceId
        self.day = day
        self.of = of
        self.rule = rule
        self.until = until
    }

    enum CodingKeys: String, CodingKey { case raceId, day, of, rule, until }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let day = c.lenientInt(.day), let of = c.lenientInt(.of), day >= 1, of >= day else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "recovery window without a day of a length"))
        }
        self.day = day
        self.of = of
        raceId = c.lenientString(.raceId)
        rule = c.lenientString(.rule)
        until = c.lenient(LocalDate.self, .until)
    }
}

// MARK: - Notices

/// One of the projection's `notices`: `{ kind, date, en, cz }`. The text is
/// the vault's; an unknown `kind` is shown all the same.
public struct ProjectionNotice: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "notice"
    /// The one kind of 2026-10-01: nothing synced from the watch for days.
    public static let noActivitiesSince = "no-activities-since"

    public var kind: String?
    public var date: LocalDate?
    public var text: LocalizedText

    public init(kind: String?, date: LocalDate? = nil, text: LocalizedText) {
        self.kind = kind
        self.date = date
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case kind, date, en, cz, cs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenientString(.kind)
        date = c.lenient(LocalDate.self, .date)
        var values: [String: String] = [:]
        values["en"] = c.lenientString(.en)
        values["cz"] = c.lenientString(.cz)
        values["cs"] = c.lenientString(.cs)
        text = LocalizedText(values: values)
        if text.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "notice without a text"))
        }
    }
}

// MARK: - Done without a watch

/// `done.manual`: the app's `session.done` as the vault kept it. Present
/// beside a matched activity too -- then the activity won and this is only
/// the note of what was said.
public struct ManualDone: Equatable, Sendable, Decodable {
    public var date: LocalDate?
    public var option: OpenEnum<OptionCode>?
    public var min: Int?
    public var km: Double?
    public var note: String?
    /// The id of the event that said it.
    public var event: String?

    public init(date: LocalDate? = nil, option: OpenEnum<OptionCode>? = nil, min: Int? = nil, km: Double? = nil, note: String? = nil, event: String? = nil) {
        self.date = date
        self.option = option
        self.min = min
        self.km = km
        self.note = note
        self.event = event
    }

    enum CodingKeys: String, CodingKey { case date, option, min, km, note, event }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.lenient(LocalDate.self, .date)
        option = c.lenient(OpenEnum<OptionCode>.self, .option)
        min = c.lenientInt(.min)
        km = c.lenientDouble(.km)
        note = c.lenientString(.note)
        event = c.lenientString(.event)
    }
}

// MARK: - The fuel log

/// `session.feedback.fuel`: what was eaten during the session, with the
/// vault's grams per hour against the plan. `carbsG: 0` is a fact.
public struct FuelLog: Equatable, Sendable, Decodable {
    public var carbsG: Double?
    public var fluidMl: Int?
    /// The minutes `gPerH` was computed over; `nil` = unknown.
    public var durationMin: Int?
    public var gPerH: Int?
    public var planGPerH: Double?
    public var vsPlan: OpenEnum<FuelVsPlan>?
    public var note: String?

    public init(carbsG: Double? = nil, fluidMl: Int? = nil, durationMin: Int? = nil, gPerH: Int? = nil, planGPerH: Double? = nil, vsPlan: OpenEnum<FuelVsPlan>? = nil, note: String? = nil) {
        self.carbsG = carbsG
        self.fluidMl = fluidMl
        self.durationMin = durationMin
        self.gPerH = gPerH
        self.planGPerH = planGPerH
        self.vsPlan = vsPlan
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case carbsG, fluidMl, durationMin, gPerH, planGPerH, vsPlan, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carbsG = c.lenientDouble(.carbsG)
        fluidMl = c.lenientInt(.fluidMl)
        durationMin = c.lenientInt(.durationMin)
        gPerH = c.lenientInt(.gPerH)
        planGPerH = c.lenientDouble(.planGPerH)
        vsPlan = c.lenient(OpenEnum<FuelVsPlan>.self, .vsPlan)
        note = c.lenientString(.note)
    }
}

// MARK: - Race results

/// `season.races[].result`. `status` is `nil` only for a report that states
/// none. `goalReached` and `pr` are never inferred by anyone but the vault
/// and its report: `nil` is "not known", never "no".
public struct RaceResult: Equatable, Sendable, Decodable {
    public var status: OpenEnum<RaceOutcome>?
    public var reason: OpenEnum<RaceResultReason>?
    /// The ELAPSED time, `h:mm:ss`, pauses included.
    public var time: String?
    /// The organiser's results time when it is another one; never a copy
    /// of `time`.
    public var officialTime: String?
    public var distanceKm: Double?
    public var laps: Int?
    public var goalReached: Bool?
    public var pr: Bool?
    /// A vault path: decoded, never shown.
    public var reportPath: String?
    public var source: OpenEnum<RaceResultSource>?
    public var note: String?

    public init(
        status: OpenEnum<RaceOutcome>? = nil,
        reason: OpenEnum<RaceResultReason>? = nil,
        time: String? = nil,
        officialTime: String? = nil,
        distanceKm: Double? = nil,
        laps: Int? = nil,
        goalReached: Bool? = nil,
        pr: Bool? = nil,
        reportPath: String? = nil,
        source: OpenEnum<RaceResultSource>? = nil,
        note: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.time = time
        self.officialTime = officialTime
        self.distanceKm = distanceKm
        self.laps = laps
        self.goalReached = goalReached
        self.pr = pr
        self.reportPath = reportPath
        self.source = source
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case status, reason, time, officialTime, distanceKm, laps, goalReached, pr, reportPath, source, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.lenient(OpenEnum<RaceOutcome>.self, .status)
        reason = c.lenient(OpenEnum<RaceResultReason>.self, .reason)
        time = c.lenientString(.time).flatMap { $0.isEmpty ? nil : $0 }
        officialTime = c.lenientString(.officialTime).flatMap { $0.isEmpty ? nil : $0 }
        distanceKm = c.lenientDouble(.distanceKm)
        laps = c.lenientInt(.laps)
        goalReached = c.lenientBool(.goalReached)
        pr = c.lenientBool(.pr)
        reportPath = c.lenientString(.reportPath)
        source = c.lenient(OpenEnum<RaceResultSource>.self, .source)
        note = c.lenientString(.note)
    }
}
