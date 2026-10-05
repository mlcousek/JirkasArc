// HabitFixtures.swift
//
// Synthetic, inline projections for the interactive habits
// (add-interactive-habits design D9). They are built here in code and NOT
// taken from the mirrored vault contract fixtures: those are re-mirrored
// whenever the vault's example changes, which must not move these goldens.
//
// The season is the vault example's (2030), nothing else is shared with it:
// four written weeks, 2030-10-07 ... 2030-11-03, "today" Wednesday
// 2030-10-23, a file written for the day before (`asOf` 2030-10-22), and a
// five-step ladder --
//
//   holds    step 0, active, twice a day
//   gym      step 1, active, Monday and Thursday
//   walk     step 2, active, every day (the current step)
//   stretch  step 3, next
//   swim     step 4, later
//
// with the days' counts below known for 7 ... 22 October and unknown from
// today on. By default the habits carry none of the vault's `streak` /
// `history` / `adherence` (an older file: the phone's fallback); a test
// adds them through `walkExtra` / `holdsExtra`. No real data: invented
// habits and numbers.
//
// Every nested literal is typed on purpose: Swift does not infer a
// heterogeneous `[String: Any]` inside another literal.

import Foundation
import XCTest
@testable import TrainingCore

enum HabitFixtures {
    static let today = D.date("2030-10-23")
    static let firstDay = D.date("2030-10-07")
    static let lastDay = D.date("2030-11-03")
    /// The last day with counts, and the day the file is written for.
    static let lastRecorded = D.date("2030-10-22")
    /// The phone's device id in `tick` and `refusal`.
    static let deviceID = "ios-0000beef"

    /// walk: done every day but the 8th and the 16th.
    static let walk: [String: Int] = [
        "2030-10-07": 1, "2030-10-08": 0, "2030-10-09": 1, "2030-10-10": 1,
        "2030-10-11": 1, "2030-10-12": 1, "2030-10-13": 1, "2030-10-14": 1,
        "2030-10-15": 1, "2030-10-16": 0, "2030-10-17": 1, "2030-10-18": 1,
        "2030-10-19": 1, "2030-10-20": 1, "2030-10-21": 1, "2030-10-22": 1
    ]

    /// holds: two doses a day (uncapped counts).
    static let holds: [String: Int] = [
        "2030-10-07": 2, "2030-10-08": 2, "2030-10-09": 2, "2030-10-10": 2,
        "2030-10-11": 1, "2030-10-12": 2, "2030-10-13": 4, "2030-10-14": 2,
        "2030-10-15": 1, "2030-10-16": 0, "2030-10-17": 2, "2030-10-18": 1,
        "2030-10-19": 2, "2030-10-20": 2, "2030-10-21": 0, "2030-10-22": 2
    ]

    /// gym: Mondays and Thursdays; the 10th was missed.
    static let gym: [String: Int] = [
        "2030-10-07": 1, "2030-10-10": 0, "2030-10-14": 1, "2030-10-17": 1, "2030-10-21": 1
    ]

    static func habit(_ id: String, step: Int, label: [String: String], state: String, schedule: [String: Any], extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = [:]
        object["id"] = id
        object["step"] = step
        object["label"] = label
        object["state"] = state
        object["schedule"] = schedule
        for (key, value) in extra {
            object[key] = value
        }
        return object
    }

    /// The five-step ladder; `walkExtra` / `holdsExtra` add fields to that
    /// habit (the vault's `streak`, `history`, `adherence`, a `source`).
    static func ladder(walkExtra: [String: Any] = [:], holdsExtra: [String: Any] = [:]) -> [[String: Any]] {
        let twiceADay: [String: Any] = ["kind": "daily", "perDay": 2]
        let mondayAndThursday: [String: Any] = ["kind": "weekly", "days": ["MO", "TH"]]
        let everyDay: [String: Any] = ["kind": "daily"]
        let afterEasyRuns: [String: Any] = ["kind": "withSessions", "sport": "run", "types": ["easy"]]
        let onceAWeek: [String: Any] = ["kind": "weeklyCount", "times": 1]
        return [
            habit("holds", step: 0, label: ["en": "Holds", "cz": "Výdrže"], state: "active", schedule: twiceADay, extra: holdsExtra),
            habit("gym", step: 1, label: ["en": "Gym twice a week", "cz": "Posilovna 2× týdně"], state: "active", schedule: mondayAndThursday),
            habit("walk", step: 2, label: ["en": "Morning walk", "cz": "Ranní procházka"], state: "active", schedule: everyDay, extra: walkExtra),
            habit("stretch", step: 3, label: ["en": "Stretch after easy runs", "cz": "Protažení po klidném běhu"], state: "next", schedule: afterEasyRuns),
            habit("swim", step: 4, label: ["en": "Swim", "cz": "Plavání"], state: "later", schedule: onceAWeek)
        ]
    }

    /// The projection as JSON. `asOf` is the day the file is written for;
    /// `outcomes` its top-level `outcomes`; `dayChange` edits a day's
    /// object (keys `habitsExpected`, `habitsDone`) after the defaults are
    /// filled in.
    static func data(
        ladder: [[String: Any]] = HabitFixtures.ladder(),
        asOf: LocalDate = HabitFixtures.lastRecorded,
        outcomes: [[String: Any]] = [],
        dayChange: (LocalDate, inout [String: Any]) -> Void = { _, _ in }
    ) throws -> Data {
        var weeks: [[String: Any]] = []
        var monday = firstDay
        while monday <= lastDay {
            var days: [[String: Any]] = []
            for offset in 0..<7 {
                let date = monday.adding(days: offset)
                let key = date.description
                var expected: [String] = ["holds", "walk"]
                if date.isoWeekday == 1 || date.isoWeekday == 4 { expected.append("gym") }
                var day: [String: Any] = [:]
                day["date"] = key
                day["habitsExpected"] = expected
                day["sessions"] = [String]()
                if date <= lastRecorded {
                    let counts: [String: Int] = ["holds": holds[key] ?? 0, "walk": walk[key] ?? 0, "gym": gym[key] ?? 0]
                    day["habitsDone"] = counts
                } else {
                    day["habitsDone"] = NSNull()
                }
                dayChange(date, &day)
                days.append(day)
            }
            var week: [String: Any] = [:]
            week["week"] = ISOWeek(containing: monday).description
            week["from"] = monday.description
            week["to"] = monday.adding(days: 6).description
            week["days"] = days
            weeks.append(week)
            monday = monday.adding(days: 7)
        }
        let gate: [String: Int] = ["adherencePct": 80, "windowDays": 14]
        var habits: [String: Any] = [:]
        habits["gate"] = gate
        habits["ladder"] = ladder
        var athlete: [String: Any] = [:]
        athlete["tz"] = "Europe/Prague"
        athlete["dayBoundaryHour"] = 3
        var plan: [String: Any] = [:]
        plan["id"] = "synthetic-base"
        plan["weeks"] = weeks
        var object: [String: Any] = [:]
        object["schema"] = "hub.projection"
        object["schemaVersion"] = 1
        object["asOf"] = asOf.description
        object["athlete"] = athlete
        object["plan"] = plan
        object["habits"] = habits
        object["outcomes"] = outcomes
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func projection(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> Projection {
        switch ProjectionDecoder.decode(data) {
        case .success(let decoded): return decoded.projection
        case .failure(let rejection):
            XCTFail("habit fixture did not decode: \(rejection)", file: file, line: line)
            throw rejection
        }
    }

    /// A recorded tick of the phone (device `ios-0000beef`, event id
    /// `habit-<seq>`).
    static func tick(_ habit: String, _ date: String, done: Bool, seq: Int, segment: UUID? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(
                id: "habit-\(seq)",
                deviceId: deviceID,
                seq: seq,
                at: "t",
                payload: .habitTick(HabitTickPayload(date: D.date(date), habitId: habit, done: done))
            ),
            recordedAt: Date(timeIntervalSince1970: 1_918_951_651 + Double(seq)),
            segmentID: segment
        )
    }

    /// The vault's refusal of the tick `tick(..., seq:)` made, as an entry
    /// of the projection's `outcomes` (the contract's shape). `reason`:
    /// `{ en, cz }`, or `nil` for an entry without one.
    static func refusal(seq: Int, reason: [String: String]? = ["en": "That day is more than 14 days back.", "cz": "Ten den je víc než 14 dní zpátky."]) -> [String: Any] {
        var outcome: [String: Any] = [:]
        outcome["event"] = "habit-\(seq)"
        outcome["deviceId"] = deviceID
        outcome["seq"] = seq
        outcome["type"] = "habit.tick"
        outcome["week"] = NSNull()
        outcome["sessionId"] = NSNull()
        outcome["status"] = "refused"
        if let reason {
            outcome["reason"] = reason
        } else {
            outcome["reason"] = NSNull()
        }
        return outcome
    }

    /// The snapshot the screens see: the projection, the phone's `ticks`
    /// folded over it with the projection's own `outcomes` (like
    /// `TrainingRecorder.overlay`), and whether it may record.
    static func snapshot(
        _ data: Data? = nil,
        ticks: [LoggedEvent] = [],
        canRecord: Bool = true,
        unsent: Set<UUID> = []
    ) throws -> TrainingSnapshot {
        let bytes = try data ?? HabitFixtures.data()
        let decoded = try projection(bytes)
        let overlay = CheckInOverlay.fold(ticks, unsentSegments: unsent, outcomes: PlanOutcome.parse(decoded.outcomes))
        return TrainingSnapshot(
            projection: decoded,
            checkIns: overlay,
            capabilities: .checkIns(enabled: canRecord)
        )
    }

    /// 83 days of history ending the day before today, every day expected
    /// once and done once except `missed` (listed with `done: 0`, as the
    /// vault lists a missed or silent day).
    static func history(missed: Set<String> = []) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        for offset in stride(from: 83, through: 1, by: -1) {
            let key = today.adding(days: -offset).description
            var entry: [String: Any] = [:]
            entry["date"] = key
            entry["expected"] = 1
            entry["done"] = missed.contains(key) ? 0 : 1
            entries.append(entry)
        }
        return entries
    }

    /// The vault's fields on the walk: a long streak, the 83-day history
    /// and a full adherence.
    static func published(missed: Set<String> = [], unit: String = "day", source: String? = nil) -> [String: Any] {
        var streak: [String: Any] = [:]
        streak["current"] = 120
        streak["best"] = 130
        streak["unit"] = unit
        streak["lastDone"] = "2030-10-22"
        let adherence: [String: Int] = ["d7": 100, "d14": 100, "d30": 100, "d84": 100]
        var extra: [String: Any] = [:]
        extra["streak"] = streak
        extra["history"] = history(missed: missed)
        extra["adherence"] = adherence
        if let source {
            extra["source"] = source
        }
        return extra
    }
}
