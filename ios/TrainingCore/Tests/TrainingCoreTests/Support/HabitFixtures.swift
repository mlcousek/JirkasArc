// HabitFixtures.swift
//
// Synthetic, inline projections for the interactive habits
// (add-interactive-habits design D9). They are built here in code and NOT
// taken from the mirrored vault contract fixtures: the vault's `streak` /
// `history` / `adherence` contract is still in progress and those fixtures
// are re-mirrored in a later step, which must not move these goldens.
//
// The season is the vault example's (2030), nothing else is shared with it:
// four written weeks, 2030-10-07 ... 2030-11-03, "today" Wednesday
// 2030-10-23, and a five-step ladder --
//
//   holds    step 0, active, twice a day
//   gym      step 1, active, Monday and Thursday
//   walk     step 2, active, every day (the current step)
//   stretch  step 3, next
//   swim     step 4, later
//
// with the days' counts below known for 7 ... 22 October and unknown from
// today on. No real data: invented habits and numbers.

import Foundation
import XCTest
@testable import TrainingCore

enum HabitFixtures {
    static let today = D.date("2030-10-23")
    static let firstDay = D.date("2030-10-07")
    static let lastDay = D.date("2030-11-03")
    /// The last day with counts.
    static let lastRecorded = D.date("2030-10-22")

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
        var object: [String: Any] = [
            "id": id,
            "step": step,
            "label": label,
            "state": state,
            "schedule": schedule
        ]
        for (key, value) in extra {
            object[key] = value
        }
        return object
    }

    /// The five-step ladder; `walkExtra` adds fields to the walk (the
    /// vault's `streak`, `history`, `adherence`).
    static func ladder(walkExtra: [String: Any] = [:], holdsExtra: [String: Any] = [:]) -> [[String: Any]] {
        [
            habit("holds", step: 0, label: ["en": "Holds", "cz": "Výdrže"], state: "active", schedule: ["kind": "daily", "perDay": 2], extra: holdsExtra),
            habit("gym", step: 1, label: ["en": "Gym twice a week", "cz": "Posilovna 2× týdně"], state: "active", schedule: ["kind": "weekly", "days": ["MO", "TH"]]),
            habit("walk", step: 2, label: ["en": "Morning walk", "cz": "Ranní procházka"], state: "active", schedule: ["kind": "daily"], extra: walkExtra),
            habit("stretch", step: 3, label: ["en": "Stretch after easy runs", "cz": "Protažení po klidném běhu"], state: "next", schedule: ["kind": "withSessions", "sport": "run", "types": ["easy"]]),
            habit("swim", step: 4, label: ["en": "Swim", "cz": "Plavání"], state: "later", schedule: ["kind": "weeklyCount", "times": 1])
        ]
    }

    /// The projection as JSON. `dayChange` edits a day's object (keys
    /// `habitsExpected`, `habitsDone`) after the defaults are filled in.
    static func data(
        ladder: [[String: Any]] = HabitFixtures.ladder(),
        backfillDays: Any? = nil,
        dayChange: (LocalDate, inout [String: Any]) -> Void = { _, _ in }
    ) throws -> Data {
        var weeks: [[String: Any]] = []
        var monday = firstDay
        while monday <= lastDay {
            var days: [[String: Any]] = []
            for offset in 0..<7 {
                let date = monday.adding(days: offset)
                let key = date.description
                var expected = ["holds", "walk"]
                if date.isoWeekday == 1 || date.isoWeekday == 4 { expected.append("gym") }
                var day: [String: Any] = ["date": key, "habitsExpected": expected, "sessions": []]
                if date <= lastRecorded {
                    day["habitsDone"] = ["holds": holds[key] ?? 0, "walk": walk[key] ?? 0, "gym": gym[key] ?? 0]
                } else {
                    day["habitsDone"] = NSNull()
                }
                dayChange(date, &day)
                days.append(day)
            }
            weeks.append([
                "week": ISOWeek(containing: monday).description,
                "from": monday.description,
                "to": monday.adding(days: 6).description,
                "days": days
            ])
            monday = monday.adding(days: 7)
        }
        var habits: [String: Any] = [
            "gate": ["adherencePct": 80, "windowDays": 14],
            "ladder": ladder
        ]
        if let backfillDays {
            habits["backfillDays"] = backfillDays
        }
        let object: [String: Any] = [
            "schema": "hub.projection",
            "schemaVersion": 1,
            "asOf": lastRecorded.description,
            "athlete": ["tz": "Europe/Prague", "dayBoundaryHour": 3],
            "plan": ["id": "synthetic-base", "weeks": weeks],
            "habits": habits
        ]
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

    /// A recorded tick of the phone (device `ios-0000beef`).
    static func tick(_ habit: String, _ date: String, done: Bool, seq: Int, segment: UUID? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(
                id: "habit-\(seq)",
                deviceId: "ios-0000beef",
                seq: seq,
                at: "t",
                payload: .habitTick(HabitTickPayload(date: D.date(date), habitId: habit, done: done))
            ),
            recordedAt: Date(timeIntervalSince1970: 1_918_951_651 + Double(seq)),
            segmentID: segment
        )
    }

    static func snapshot(
        _ data: Data? = nil,
        ticks: [LoggedEvent] = [],
        canRecord: Bool = true,
        unsent: Set<UUID> = []
    ) throws -> TrainingSnapshot {
        TrainingSnapshot(
            projection: try projection(try data ?? HabitFixtures.data()),
            checkIns: CheckInOverlay.fold(ticks, unsentSegments: unsent),
            capabilities: .checkIns(enabled: canRecord)
        )
    }

    /// 83 days of history ending the day before today, every day expected
    /// once and done once except `missed`.
    static func history(missed: Set<String> = []) -> [[String: Any]] {
        (1...83).reversed().map { offset -> [String: Any] in
            let key = today.adding(days: -offset).description
            return ["date": key, "expected": 1, "done": missed.contains(key) ? 0 : 1]
        }
    }
}
