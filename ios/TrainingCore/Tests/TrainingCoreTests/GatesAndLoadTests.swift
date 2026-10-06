// GatesAndLoadTests.swift
//
// add-training-gates-and-load, on the vault's two contract fixtures (and
// small mutations of the example): the fields the vault added on
// 2026-10-01 and 2026-10-05 decode tolerantly (a missing number is unknown,
// never 0); the phone's own gate tests, session pains, completions by hand,
// fuel logs and race results fold like the vault folds them; and the models
// the screens draw -- the gate card, "the plan is the ceiling", the
// recovery chip, the vault's notices, pain during / after, "Mark done (no
// watch)", the fuel log, the race result with its two times -- say what the
// VAULT said, in English and Czech. Nothing here is real data: the season
// is the vault's synthetic 2030/31.

import XCTest
@testable import TrainingCore

final class GatesAndLoadTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651)
    private let device = "ios-0000beef"
    /// The event the example's gym session is done by (the vault's seq 26).
    private let gymDoneEvent = "01beca79-e480-711a-a11a-5eed0000001a"

    // MARK: Helpers

    private func logged(_ payload: HubEventPayload, seq: Int, id: String? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: id ?? "id-\(seq)", deviceId: device, seq: seq, at: "t", payload: payload),
            recordedAt: t0.addingTimeInterval(Double(seq)),
            segmentID: nil
        )
    }

    private func projection(_ data: Data? = nil) throws -> Projection {
        guard let data else { return try Fixtures.exampleProjection().projection }
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return decoded.projection
    }

    private func fold(_ events: [LoggedEvent], acked: Int? = nil, outcomes: [PlanOutcome] = []) -> CheckInOverlay {
        var ackedSeqs: [String: Int] = [:]
        if let acked { ackedSeqs[device] = acked }
        return CheckInOverlay.fold(events, unsentSegments: [], ackedSeqs: ackedSeqs, outcomes: outcomes)
    }

    private func snapshot(
        _ events: [LoggedEvent] = [],
        acked: Int? = nil,
        outcomes: [PlanOutcome] = [],
        data: Data? = nil,
        recording: Bool = true
    ) throws -> TrainingSnapshot {
        TrainingSnapshot(
            projection: try projection(data),
            checkIns: fold(events, acked: acked, outcomes: outcomes),
            capabilities: .recording(enabled: recording)
        )
    }

    private func today(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english, on date: LocalDate = D.asOf) -> TodayTrainingBuilder {
        TodayTrainingBuilder(source: .loaded(snapshot), language: language, today: date)
    }

    private func plan(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english, on date: LocalDate = D.asOf) -> PlanBuilder {
        PlanBuilder(source: .loaded(snapshot), language: language, today: date)
    }

    private func mutatedAthlete(_ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try Fixtures.mutatedExample { object in
            var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
            change(&athlete)
            object["athlete"] = athlete
        }
    }

    private func mutatedGate(_ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutatedAthlete { athlete in
            guard var gate = athlete["gate"] as? [String: Any] else { return }
            change(&gate)
            athlete["gate"] = gate
        }
    }

    private func mutatedRecovery(_ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutatedAthlete { athlete in
            guard var recovery = athlete["recovery"] as? [String: Any] else { return }
            change(&recovery)
            athlete["recovery"] = recovery
        }
    }

    private func mutatedActual(week: Int, _ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try Fixtures.mutatedExample { object in
            var plan = try XCTUnwrap(object["plan"] as? [String: Any])
            var weeks = try XCTUnwrap(plan["weeks"] as? [[String: Any]])
            var actual = try XCTUnwrap(weeks[week]["actual"] as? [String: Any])
            change(&actual)
            weeks[week]["actual"] = actual
            plan["weeks"] = weeks
            object["plan"] = plan
        }
    }

    private func mutatedRace(_ id: String, _ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            let index = try Fixtures.raceIndex(races, id: id)
            change(&races[index])
            season["races"] = races
            object["season"] = season
        }
    }

    private func withoutPainMode() throws -> Data {
        try mutatedAthlete { athlete in
            athlete["painMode"] = ["active": false, "since": NSNull(), "sites": [String](), "reason": NSNull(), "clearsAfter": NSNull()] as [String: Any]
        }
    }

    private let loadKeys = ["plannedRunKm", "unplannedRunKm", "overPlanKm", "longestRunKm", "longestRunCapKm", "hillM", "highSessions"]

    // MARK: - Decoding

    func testTheExampleCarriesTheGateTheRecoveryWindowAndTheLoad() throws {
        let decoded = try Fixtures.exampleProjection()
        XCTAssertTrue(decoded.issues.isEmpty, decoded.issues.summary ?? "")
        let projection = decoded.projection

        XCTAssertEqual(projection.athlete.gate, GateStatus(
            date: D.asOf, walkPain: 1.5, hopPain: 4, site: .achillesLeft,
            runAllowed: true, speedAllowed: false, weeksHopAbove2: 1, stale: false,
            note: "20 single-leg hops, sharp on landing"
        ))
        XCTAssertEqual(projection.athlete.recovery, RecoveryWindow(raceId: "harvest-marathon-2030", day: 10, of: 14, rule: "PM-SEQ-1", until: D.date("2030-10-27")))
        XCTAssertEqual(projection.notices, [])

        let plan = try XCTUnwrap(projection.plan)
        let w42 = try XCTUnwrap(plan.weeks[1].actual)
        XCTAssertEqual(w42.runKm, 60.1)
        XCTAssertEqual(w42.plannedRunKm, 54.1)
        XCTAssertEqual(w42.unplannedRunKm, 6)
        XCTAssertEqual(w42.overPlanKm, 5.1)
        XCTAssertEqual(w42.longestRunKm, 17.5)
        XCTAssertEqual(w42.longestRunCapKm, 13.6)
        XCTAssertEqual(w42.hillM, 460)
        XCTAssertEqual(w42.highSessions, 0)
        XCTAssertTrue(w42.hasLoadFields)
        XCTAssertNil(plan.weeks[3].actual, "a week ahead has no actual at all")

        // One unplanned run is over plan; the ride the day before is not.
        let flagged = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-16"))?.unplanned.first)
        XCTAssertEqual(flagged.flag, .known(.overPlan))
        XCTAssertTrue(flagged.isOverPlan)
        let ride = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-15"))?.unplanned.first)
        XCTAssertNil(ride.flag)
        XCTAssertFalse(ride.isOverPlan)
    }

    func testTheExampleCarriesManualRecordsSessionPainAndTheFuelLog() throws {
        let plan = try XCTUnwrap(try Fixtures.exampleProjection().projection.plan)
        let gym = try XCTUnwrap(plan.weeks[2].day(D.date("2030-10-21"))?.sessions.first)
        XCTAssertEqual(gym.done?.manual, ManualDone(date: D.date("2030-10-21"), option: nil, min: 45, km: nil, note: "Gym A done, watch left at home", event: gymDoneEvent))
        XCTAssertEqual(gym.done?.isManual, true)

        // An activity that won over a manual record keeps the record.
        let tempo = try XCTUnwrap(plan.weeks[2].day(D.date("2030-10-22"))?.sessions.first)
        XCTAssertEqual(tempo.done?.isManual, false)
        XCTAssertNotNil(tempo.done?.activity)
        XCTAssertEqual(tempo.done?.manual?.min, 55)
        XCTAssertEqual(tempo.done?.manual?.km, 10)
        XCTAssertNil(tempo.done?.manual?.note)
        XCTAssertEqual(tempo.feedback?.pains, [
            SessionPainEntry(site: .achillesLeft, during: 4, after: 6),
            SessionPainEntry(site: .kneeRight, during: nil, after: 1)
        ])
        XCTAssertNil(tempo.feedback?.fuel)

        let longRun = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-19"))?.sessions.first)
        XCTAssertNil(longRun.feedback?.pains, "pain was never asked with that RPE")
        XCTAssertEqual(longRun.feedback?.fuel, FuelLog(
            carbsG: 90, fluidMl: 750, durationMin: 118, gPerH: 46, planGPerH: 60, vsPlan: .known(.below),
            note: "Two gels and a bar; the third gel stayed in the vest"
        ))
    }

    func testTheExampleCarriesRaceResultsLookedUpById() throws {
        let snap = try snapshot()
        XCTAssertEqual(snap.races.map(\.id), ["lakeside-10k-2030", "harvest-marathon-2030", "valley-30k-2030", "ridge-ultra-2031"])

        let lakeside = try XCTUnwrap(snap.race(id: "lakeside-10k-2030")?.result)
        XCTAssertEqual(lakeside.status, .known(.finished))
        XCTAssertNil(lakeside.reason)
        XCTAssertEqual(lakeside.time, "0:46:03", "the elapsed time")
        XCTAssertEqual(lakeside.officialTime, "0:45:41", "the organiser's, another one")
        XCTAssertEqual(lakeside.distanceKm, 10)
        XCTAssertNil(lakeside.laps)
        XCTAssertEqual(lakeside.goalReached, false)
        XCTAssertEqual(lakeside.pr, true)
        XCTAssertEqual(lakeside.source, .known(.report))
        XCTAssertNotNil(lakeside.reportPath)

        let marathon = try XCTUnwrap(snap.race(id: "harvest-marathon-2030")?.result)
        XCTAssertEqual(marathon.status, .known(.finished))
        XCTAssertEqual(marathon.time, "3:24:10")
        XCTAssertNil(marathon.officialTime, "never filled from the elapsed time")
        XCTAssertEqual(marathon.distanceKm, 42.2)
        XCTAssertEqual(marathon.goalReached, true)
        XCTAssertNil(marathon.pr, "not known is not no")
        XCTAssertEqual(marathon.source, .known(.event))
        XCTAssertEqual(marathon.note, "Even pace, strong last 5 km")

        XCTAssertNil(snap.race(id: "valley-30k-2030")?.result)
        XCTAssertNil(snap.race(id: "ridge-ultra-2031")?.result)
        XCTAssertNil(snap.race(id: "no-such-race"))
    }

    func testTheMinimalFileHasNoGateAndOneNotice() throws {
        let projection = try projection(try Fixtures.minimal())
        XCTAssertNil(projection.athlete.gate)
        XCTAssertNil(projection.athlete.recovery)
        XCTAssertEqual(projection.notices.count, 1)
        let notice = try XCTUnwrap(projection.notices.first)
        XCTAssertEqual(notice.kind, ProjectionNotice.noActivitiesSince)
        XCTAssertNil(notice.date)
        XCTAssertTrue(notice.text.resolved(.english).hasPrefix("No synced activity was found"))
        XCTAssertTrue(notice.text.resolved(.czech).hasPrefix("Mezi 2030-09-07"))
    }

    func testAnOlderFileDecodesWithNoneOfIt() throws {
        let keys = loadKeys
        let older = try Fixtures.mutatedExample { object in
            object["notices"] = nil
            var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
            athlete["gate"] = nil
            athlete["recovery"] = nil
            object["athlete"] = athlete
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            for index in races.indices { races[index]["result"] = nil }
            season["races"] = races
            object["season"] = season
            var plan = try XCTUnwrap(object["plan"] as? [String: Any])
            var weeks = try XCTUnwrap(plan["weeks"] as? [[String: Any]])
            for index in weeks.indices {
                guard var actual = weeks[index]["actual"] as? [String: Any] else { continue }
                for key in keys { actual[key] = nil }
                weeks[index]["actual"] = actual
            }
            plan["weeks"] = weeks
            object["plan"] = plan
        }
        let projection = try projection(older)
        XCTAssertNil(projection.athlete.gate)
        XCTAssertNil(projection.athlete.recovery)
        XCTAssertEqual(projection.notices, [])
        XCTAssertTrue(projection.season?.races.allSatisfy { $0.result == nil } ?? false)
        let actual = try XCTUnwrap(projection.plan?.weeks[1].actual)
        XCTAssertEqual(actual.runKm, 60.1, "what an older file had is still read")
        XCTAssertFalse(actual.hasLoadFields)
        // The week keeps its plain run line and has no load line.
        let week = plan(TrainingSnapshot(projection: projection)).week(D.week("2030-W42"))
        XCTAssertNil(week.load)
        XCTAssertEqual(week.runLine, "Run 60.1 of 55 km")
    }

    func testADataGapIsUnknownNeverZero() throws {
        let gaps = try mutatedActual(week: 1) { actual in
            actual["overPlanKm"] = NSNull()
            actual["longestRunCapKm"] = NSNull()
            actual["hillM"] = "many"
            actual["highSessions"] = NSNull()
        }
        let actual = try XCTUnwrap(try projection(gaps).plan?.weeks[1].actual)
        XCTAssertNil(actual.overPlanKm)
        XCTAssertNil(actual.longestRunCapKm)
        XCTAssertNil(actual.hillM, "a wrong type is unknown too")
        XCTAssertNil(actual.highSessions)
        XCTAssertEqual(actual.unplannedRunKm, 6)
        XCTAssertTrue(actual.hasLoadFields)

        let model = try XCTUnwrap(plan(try snapshot(data: gaps)).week(D.week("2030-W42")).load)
        XCTAssertEqual(model.text, "Week 60.1 of 55 km · 6 km unplanned · longest 17.5 of – km cap · hills – m · hard sessions –")
        XCTAssertFalse(model.hasWarning, "no cap, no spike; no over-plan figure, no warning")
    }

    func testUnknownValuesAreKeptAndBrokenOnesDropped() throws {
        let data = try Fixtures.mutatedExample { object in
            let unknownKind: [String: Any] = ["kind": "watch-battery", "date": "2030-10-20", "en": "A new kind of notice.", "cz": "Nový druh upozornění."]
            let withoutText: [String: Any] = ["kind": "no-activities-since", "date": NSNull()]
            let notices: [Any] = [unknownKind, withoutText, "not a notice"]
            object["notices"] = notices
            var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
            athlete["recovery"] = ["raceId": "r", "day": 0, "of": 14, "rule": "PM-SEQ-1", "until": "2030-10-27"] as [String: Any]
            var gate = try XCTUnwrap(athlete["gate"] as? [String: Any])
            gate["site"] = "hip-left"
            gate["runAllowed"] = NSNull()
            gate["speedAllowed"] = "yes"
            gate["weeksHopAbove2"] = NSNull()
            gate["stale"] = NSNull()
            athlete["gate"] = gate
            object["athlete"] = athlete
            try Fixtures.mutateDay(&object, week: 1, day: 2) { day in
                guard var unplanned = day["unplanned"] as? [[String: Any]], !unplanned.isEmpty else { return }
                unplanned[0]["flag"] = "way-over"
                day["unplanned"] = unplanned
            }
        }
        let projection = try projection(data)
        XCTAssertEqual(projection.notices.map(\.kind), ["watch-battery"], "an unknown kind is kept; an entry without a text is dropped")
        XCTAssertEqual(projection.notices.first?.date, D.date("2030-10-20"))
        XCTAssertNil(projection.athlete.recovery, "day 0 of 14 is not a window")
        let gate = try XCTUnwrap(projection.athlete.gate)
        XCTAssertEqual(gate.site, .other, "an unknown site reads as other")
        XCTAssertNil(gate.runAllowed, "the vault did not say")
        XCTAssertNil(gate.speedAllowed)
        XCTAssertNil(gate.weeksHopAbove2)
        XCTAssertFalse(gate.stale)
        let flagged = try XCTUnwrap(projection.plan?.weeks[1].day(D.date("2030-10-16"))?.unplanned.first)
        XCTAssertEqual(flagged.flag, .unknown("way-over"))
        XCTAssertFalse(flagged.isOverPlan)
    }

    // MARK: - The phone's fold

    func testGateTestsFoldLastPerDate() {
        let first = GateTestPayload(date: D.asOf, walkPain: 2, hopPain: 5, site: .achillesLeft)
        let corrected = GateTestPayload(date: D.asOf, walkPain: 1, hopPain: 3.5, site: .achillesLeft, note: "second try")
        let earlier = GateTestPayload(date: D.date("2030-10-19"), walkPain: 3, hopPain: 6)
        let overlay = fold([logged(.testGate(first), seq: 1), logged(.testGate(corrected), seq: 2), logged(.testGate(earlier), seq: 3)])
        XCTAssertEqual(overlay.gateTest(on: D.asOf)?.value, corrected)
        XCTAssertEqual(overlay.gateTest(on: D.asOf)?.delivery, .savedOnPhone)
        XCTAssertEqual(overlay.latestGateTest?.value, corrected, "the newest by its date, not by when it was sent")
        XCTAssertEqual(overlay.gateTests.count, 2)
        XCTAssertFalse(overlay.isEmpty)
    }

    func testSessionPainsAreKeptOrReplacedLikeTheMorningPain() {
        let pains = [SessionPainEntry(site: .achillesLeft, during: 4, after: 6)]
        let rated = logged(.sessionRPE(SessionRPEPayload(date: D.asOf, sessionId: "s", rpe: 7, pains: pains)), seq: 1)
        let corrected = logged(.sessionRPE(SessionRPEPayload(date: D.asOf, sessionId: "s", rpe: 6)), seq: 2)
        let kept = fold([rated, corrected])
        XCTAssertEqual(kept.rpe(session: "s")?.value, 6, "the new RPE")
        XCTAssertEqual(kept.pains(session: "s")?.value, pains, "a rating without pains keeps the earlier answer")

        let nothing = logged(.sessionRPE(SessionRPEPayload(date: D.asOf, sessionId: "s", rpe: 6, pains: [])), seq: 3)
        XCTAssertEqual(fold([rated, corrected, nothing]).pains(session: "s")?.value, [], "asked, nothing hurt: replaces")
        XCTAssertNil(fold([corrected]).pains(session: "s"), "not asked")
    }

    func testASessionDoneByHandShowsUntilTheVaultHasReadIt() throws {
        // Tuesday's mobility is the example's missed session.
        let done = logged(.sessionDone(SessionDonePayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-pm", min: 20)), seq: 1)

        let unread = try snapshot([done])
        let shown = try XCTUnwrap(unread.session(id: "2030-w43-tue-pm")?.session)
        XCTAssertEqual(shown.status, .known(.done))
        XCTAssertEqual(shown.done?.isManual, true)
        XCTAssertNil(shown.done?.activity)
        XCTAssertEqual(shown.done?.manual, ManualDone(date: D.date("2030-10-22"), option: nil, min: 20, km: nil, note: nil, event: "id-1"))
        let detail = try XCTUnwrap(plan(unread).sessionDetail(id: "2030-w43-tue-pm"))
        XCTAssertEqual(detail.statusText, "Done (logged by hand)")
        XCTAssertEqual(detail.done?.manualTitle, "Done without a watch")
        XCTAssertEqual(detail.done?.manualLine, "20 min")
        XCTAssertEqual(detail.manualDone?.canMark, false)
        XCTAssertEqual(detail.manualDone?.undoEventIDs, ["id-1"])
        XCTAssertEqual(detail.manualDone?.deliveryLine, "Saved on phone")
        // The week's sums are the vault's: nothing is added on the phone.
        XCTAssertEqual(plan(unread).week(D.week("2030-W43")).sessionsLine, "2 done · 1 missed of 7")

        // Acknowledged, and the file still says missed: the file decides.
        let read = try snapshot([done], acked: 1)
        XCTAssertEqual(read.session(id: "2030-w43-tue-pm")?.session.status, .known(.missed))
        let after = try XCTUnwrap(plan(read).sessionDetail(id: "2030-w43-tue-pm")?.manualDone)
        XCTAssertTrue(after.canMark)
        XCTAssertFalse(after.canUndo, "the session is not done by this event")

        // Undone before the vault read anything: back to the file's word.
        let undo = logged(.eventRetracted(EventRetractedPayload(target: "id-1")), seq: 2)
        let undone = try snapshot([done, undo])
        XCTAssertEqual(undone.session(id: "2030-w43-tue-pm")?.session.status, .known(.missed))
        XCTAssertNil(undone.checkIns.doneByHand(session: "2030-w43-tue-pm"), "a retracted fact leaves the fold")
        XCTAssertEqual(undone.checkIns.doneEventIDs(session: "2030-w43-tue-pm"), [])
    }

    func testUndoingACompletionTheVaultAlreadyCounted() throws {
        // This phone holds the very event the example's gym session is
        // done by, and the vault has read it (seq 1).
        let done = logged(.sessionDone(SessionDonePayload(date: D.date("2030-10-21"), sessionId: "2030-w43-mon-pm", min: 45)), seq: 1, id: gymDoneEvent)
        let counted = try snapshot([done], acked: 1)
        XCTAssertEqual(counted.session(id: "2030-w43-mon-pm")?.session.status, .known(.done))
        let model = try XCTUnwrap(plan(counted).sessionDetail(id: "2030-w43-mon-pm")?.manualDone)
        XCTAssertFalse(model.canMark)
        XCTAssertEqual(model.undoEventIDs, [gymDoneEvent])
        XCTAssertEqual(model.deliveryLine, "Received by the vault")
        XCTAssertEqual(model.undoTitle, "Undo")

        // The undo, not read yet: planned again on the phone.
        let undo = logged(.eventRetracted(EventRetractedPayload(target: gymDoneEvent.uppercased())), seq: 2)
        let pending = try snapshot([done, undo], acked: 1)
        let session = try XCTUnwrap(pending.session(id: "2030-w43-mon-pm")?.session)
        XCTAssertEqual(session.status, .known(.planned))
        XCTAssertNil(session.done)
        // Read by the vault, old file: the file decides again.
        let read = try snapshot([done, undo], acked: 2)
        XCTAssertEqual(read.session(id: "2030-w43-mon-pm")?.session.status, .known(.done))

        // Without this phone's event there is nothing to undo here (a
        // completion from another install).
        let foreign = try XCTUnwrap(plan(try snapshot()).sessionDetail(id: "2030-w43-mon-pm"))
        XCTAssertNil(foreign.manualDone)
    }

    func testASkippedSessionStaysSkippedAndADoneOneIsLeftAlone() throws {
        let skipped = logged(.sessionDone(SessionDonePayload(date: D.date("2030-10-28"), sessionId: "2030-w44-mon-pm", min: 45)), seq: 1)
        let matched = logged(.sessionDone(SessionDonePayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", min: 55, km: 10)), seq: 2)
        let snap = try snapshot([skipped, matched])
        XCTAssertEqual(snap.session(id: "2030-w44-mon-pm")?.session.status, .known(.skipped))
        let tempo = try XCTUnwrap(snap.session(id: "2030-w43-tue-am")?.session)
        XCTAssertNotNil(tempo.done?.activity, "an activity matched: the overlay adds nothing")
        XCTAssertEqual(tempo.done?.isManual, false)
    }

    func testFuelLogsAndRaceResultsFoldLastAndLeaveWhenRetracted() {
        let first = logged(.sessionFuel(SessionFuelPayload(date: D.asOf, sessionId: "s", carbsG: 60)), seq: 1)
        let second = logged(.sessionFuel(SessionFuelPayload(date: D.asOf, sessionId: "s", carbsG: 80, fluidMl: 500)), seq: 2)
        XCTAssertEqual(fold([first, second]).fuelLog(session: "s")?.value.carbsG, 80)
        XCTAssertEqual(fold([first, second]).fuelLog(session: "s")?.eventID, "id-2")

        let dnf = RaceResultPayload(raceId: "r", status: .dnf, reason: .stopRule, time: "5:10:00")
        let finished = RaceResultPayload(raceId: "r", status: .finished, time: "6:40:00")
        let a = logged(.raceResult(dnf), seq: 3)
        let b = logged(.raceResult(finished), seq: 4)
        let both = fold([a, b])
        XCTAssertEqual(both.raceResult(race: "r")?.payload, finished, "the last of a race wins")
        XCTAssertEqual(both.raceResultEventIDs(race: "r"), ["id-3", "id-4"])
        XCTAssertFalse(both.hasPendingRaceWithdrawal(race: "r"))

        // Withdraw retracts every live one.
        let withdrawA = logged(.eventRetracted(EventRetractedPayload(target: "id-3")), seq: 5)
        let withdrawB = logged(.eventRetracted(EventRetractedPayload(target: "id-4")), seq: 6)
        let withdrawn = fold([a, b, withdrawA, withdrawB], acked: 4)
        XCTAssertNil(withdrawn.raceResult(race: "r"))
        XCTAssertEqual(withdrawn.raceResultEventIDs(race: "r"), [])
        XCTAssertTrue(withdrawn.hasPendingRaceWithdrawal(race: "r"), "the vault has not read the retraction")
        XCTAssertFalse(fold([a, b, withdrawA, withdrawB], acked: 6).hasPendingRaceWithdrawal(race: "r"))
        // Only the newest withdrawn: the older one stands again.
        XCTAssertEqual(fold([a, b, withdrawB]).raceResult(race: "r")?.payload, dnf)
    }

    // MARK: - The gate card

    func testTheGateCardSaysTheVaultsVerdict() throws {
        let gate = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(gate.title, "Weekly gate test")
        XCTAssertEqual(gate.date, D.asOf)
        XCTAssertFalse(gate.isProminent, "a Wednesday: a link in the pain flow")
        XCTAssertTrue(gate.canRecord)
        XCTAssertEqual(gate.testedText, "Tested Wed 23 Oct")
        XCTAssertEqual(gate.lines.map(\.text), [
            "Walking 1.5/10 — running is allowed",
            "Hops 4/10 — speed, hills and jumps stay locked"
        ])
        XCTAssertEqual(gate.lines.map(\.isLocked), [false, true])
        XCTAssertFalse(gate.isStale)
        XCTAssertNil(gate.staleText)
        XCTAssertNil(gate.physioText, "one week above 2/10 is not more than two")
        XCTAssertNil(gate.emptyText)
        XCTAssertNil(gate.pendingText)
        XCTAssertEqual(gate.recordTitle, "Test again", "this ISO week already has a test")
        XCTAssertEqual(gate.initialSite, .achillesLeft)
        XCTAssertEqual(gate.initialWalk, 0)
        XCTAssertEqual(gate.scoreText(4.5), "4.5/10")
        XCTAssertEqual(gate.siteName(.kneeRight), "Knee (right)")

        let czech = try XCTUnwrap(today(try snapshot(), .czech).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(czech.lines.map(\.text), [
            "Chůze 1,5/10 — běh je povolen",
            "Poskoky 4/10 — rychlost, kopce a skoky zůstávají zamčené"
        ])
    }

    func testTheGateCardIsOnTheWeekendAndOnlyInPainMode() throws {
        let snap = try snapshot()
        let saturday = D.date("2030-10-26")
        XCTAssertEqual(today(snap, on: saturday).trainingDay(on: saturday).gate?.isProminent, true)
        let sunday = D.date("2030-11-03")
        let nextWeek = try XCTUnwrap(today(snap, on: sunday).trainingDay(on: sunday).gate)
        XCTAssertTrue(nextWeek.isProminent)
        XCTAssertEqual(nextWeek.recordTitle, "Record a test", "W44 has no test yet")
        // It describes now: not built for a day being browsed.
        XCTAssertNil(today(snap).trainingDay(on: saturday).gate)
        // Hidden outside pain mode, whatever the file's last test says.
        let healthy = try snapshot(data: try withoutPainMode())
        XCTAssertNotNil(healthy.athlete.gate)
        XCTAssertNil(today(healthy, on: saturday).trainingDay(on: saturday).gate)
        // Without a vault connection that can record, the verdict still shows.
        let readOnly = try XCTUnwrap(today(try snapshot(recording: false)).trainingDay(on: D.asOf).gate)
        XCTAssertFalse(readOnly.canRecord)
        XCTAssertEqual(readOnly.lines.count, 2)
    }

    func testNoRunningLocksSpeedTooAndNoVerdictIsNeverAllowed() throws {
        let noRunning = try mutatedGate { gate in
            gate["runAllowed"] = false
            gate["speedAllowed"] = true
        }
        let locked = try XCTUnwrap(today(try snapshot(data: noRunning)).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(locked.lines.map(\.text), [
            "Walking 1.5/10 — no running for now",
            "Hops 4/10 — speed, hills and jumps stay locked"
        ])
        XCTAssertEqual(locked.lines.map(\.isLocked), [true, true])

        let silent = try mutatedGate { gate in
            gate["runAllowed"] = NSNull()
            gate["speedAllowed"] = NSNull()
            gate["hopPain"] = NSNull()
        }
        let plain = try XCTUnwrap(today(try snapshot(data: silent)).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(plain.lines.map(\.text), ["Walking 1.5/10", "Hops –"])
        XCTAssertEqual(plain.lines.map(\.isLocked), [nil, nil])

        let allowed = try mutatedGate { gate in
            gate["hopPain"] = 1
            gate["speedAllowed"] = true
        }
        let open = try XCTUnwrap(today(try snapshot(data: allowed)).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(open.lines[1].text, "Hops 1/10 — speed, hills and jumps are allowed")
        XCTAssertEqual(open.lines[1].isLocked, false)
    }

    func testAStaleTestAndThePhysioLine() throws {
        let old = try mutatedGate { gate in
            gate["stale"] = true
            gate["weeksHopAbove2"] = 3
        }
        let gate = try XCTUnwrap(today(try snapshot(data: old)).trainingDay(on: D.asOf).gate)
        XCTAssertTrue(gate.isStale)
        XCTAssertEqual(gate.staleText, "This test is more than two weeks old.")
        XCTAssertEqual(gate.physioText, "Hops above 2/10 for 3 weeks in a row — a physio check is advised.")
        let czech = try XCTUnwrap(today(try snapshot(data: old), .czech).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(czech.physioText, "Poskoky nad 2/10 už 3 týdny v řadě — je vhodná kontrola u fyzioterapeuta.")

        let two = try mutatedGate { $0["weeksHopAbove2"] = 2 }
        XCTAssertNil(try XCTUnwrap(today(try snapshot(data: two)).trainingDay(on: D.asOf).gate).physioText, "more than two weeks, not two")
    }

    func testNoGateTestYetAndThePhonesOwnTest() throws {
        let never = try mutatedAthlete { $0["gate"] = NSNull() }
        let empty = try XCTUnwrap(today(try snapshot(data: never)).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(empty.emptyText, "No gate test yet")
        XCTAssertEqual(empty.lines, [])
        XCTAssertNil(empty.testedText)
        XCTAssertEqual(empty.recordTitle, "Record a test")
        XCTAssertEqual(empty.initialSite, .achillesLeft, "the pain episode's first Achilles site")

        // A new test of today the file does not show yet: what was sent,
        // never a verdict the phone worked out.
        let mine = logged(.testGate(GateTestPayload(date: D.asOf, walkPain: 2, hopPain: 3, site: .achillesRight, note: "after the walk")), seq: 1)
        let pending = try XCTUnwrap(today(try snapshot([mine])).trainingDay(on: D.asOf).gate)
        XCTAssertEqual(pending.pendingText, "Your test of Wed 23 Oct: walking 2/10 · hops 3/10")
        XCTAssertEqual(pending.pendingHint, "The plan answers after the next sync.")
        XCTAssertEqual(pending.deliveryLine, "Saved on phone")
        XCTAssertEqual(pending.lines.count, 2, "the vault's verdict on the test it has stays")
        XCTAssertEqual(pending.initialWalk, 2)
        XCTAssertEqual(pending.initialHop, 3)
        XCTAssertEqual(pending.initialSite, .achillesRight)
        XCTAssertEqual(pending.initialNote, "after the walk")
        // Once the vault has read it, the file alone speaks.
        XCTAssertNil(try XCTUnwrap(today(try snapshot([mine], acked: 1)).trainingDay(on: D.asOf).gate).pendingText)
        // The same test as the file's is not news either.
        let same = logged(.testGate(GateTestPayload(date: D.asOf, walkPain: 1.5, hopPain: 4, site: .achillesLeft)), seq: 1)
        XCTAssertNil(try XCTUnwrap(today(try snapshot([same])).trainingDay(on: D.asOf).gate).pendingText)
        // With no test in the file, the phone's is all there is.
        let only = try XCTUnwrap(today(try snapshot([mine], data: never)).trainingDay(on: D.asOf).gate)
        XCTAssertNil(only.emptyText)
        XCTAssertEqual(only.pendingText, "Your test of Wed 23 Oct: walking 2/10 · hops 3/10")
        XCTAssertEqual(only.recordTitle, "Test again")
    }

    func testTheGatePayloadIsOnTheHalfStepGrid() throws {
        let gate = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).gate)
        let payload = gate.payload(walk: 1.26, hop: 4.74, site: .kneeLeft, note: "   ")
        XCTAssertEqual(payload, GateTestPayload(date: D.asOf, walkPain: 1.5, hopPain: 4.5, site: .kneeLeft, note: nil))
        XCTAssertNoThrow(try HubEventPayload.testGate(payload).validate())
        XCTAssertEqual(gate.payload(walk: 12, hop: -1, site: .other, note: " sore ").walkPain, 10)
        XCTAssertEqual(gate.payload(walk: 12, hop: -1, site: .other, note: " sore ").hopPain, 0)
        XCTAssertEqual(gate.payload(walk: 12, hop: -1, site: .other, note: " sore ").note, "sore")
    }

    // MARK: - The plan is the ceiling

    func testTheWeekLoadLine() throws {
        let snap = try snapshot()
        let current = try XCTUnwrap(plan(snap).week(D.week("2030-W43")).load)
        XCTAssertEqual(current.text, "Week 10.1 of 55 km · 0 km unplanned · longest 10.1 of 19.3 km cap · hills 60 m · hard sessions 0")
        XCTAssertFalse(current.hasWarning)
        XCTAssertEqual(current.segments.map(\.kind), [.run, .unplanned, .longest, .hills, .hardSessions])
        // Today shows the same line for the shown day's week.
        XCTAssertEqual(today(snap).trainingDay(on: D.asOf).weekLoad, current)

        let over = try XCTUnwrap(plan(snap).week(D.week("2030-W42")).load)
        XCTAssertEqual(over.text, "Week 60.1 of 55 km · 5.1 km over plan · 6 km unplanned · longest 17.5 of 13.6 km cap · hills 460 m · hard sessions 0")
        XCTAssertTrue(over.hasWarning)
        XCTAssertEqual(over.segments.filter(\.isWarning).map(\.kind), [.overPlan, .longest], "over the target, and a longest run above its cap")
        XCTAssertEqual(today(snap).trainingDay(on: D.date("2030-10-16")).weekLoad, over)

        let czech = try XCTUnwrap(plan(snap, .czech).week(D.week("2030-W42")).load)
        XCTAssertEqual(czech.text, "Týden 60,1 z 55 km · 5,1 km nad plán · 6 km mimo plán · nejdelší 17,5 z limitu 13,6 km · kopce 460 m · těžké tréninky 0")

        // A week ahead has no actual: no line, the target stays.
        let ahead = plan(snap).week(D.week("2030-W44"))
        XCTAssertNil(ahead.load)
        XCTAssertEqual(ahead.runLine, "Run target 40 km")
        XCTAssertNil(today(snap).trainingDay(on: D.date("2030-10-29")).weekLoad)
    }

    func testAnOverPlanRunCarriesTheBadge() throws {
        let week = plan(try snapshot()).week(D.week("2030-W42"))
        guard case .days(let rows) = week.content else { return XCTFail("\(week.content)") }
        XCTAssertEqual(rows[2].unplanned.map(\.overPlanText), ["Over plan"])
        XCTAssertEqual(rows[1].unplanned.map(\.overPlanText), [nil], "a ride is never over the run plan")
        let czech = plan(try snapshot(), .czech).dayRow(D.date("2030-10-16"))
        XCTAssertEqual(czech.unplanned.first?.overPlanText, "Nad plán")
    }

    // MARK: - Recovery and notices

    func testTheRecoveryChipReadsItsLength() throws {
        let chip = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).recovery)
        XCTAssertEqual(chip.title, "Recovery day 10 of 14")
        XCTAssertEqual(chip.untilText, "until 27 Oct")
        XCTAssertEqual(chip.text, "Recovery day 10 of 14 · until 27 Oct")
        XCTAssertEqual(chip.raceText, "After Harvest Marathon")
        XCTAssertEqual(chip.meaningText, "Easy running only — no hard sessions yet.")
        XCTAssertEqual(chip.day, 10)
        XCTAssertEqual(chip.length, 14)
        XCTAssertEqual(chip.fraction, 10.0 / 14.0, accuracy: 1e-9)
        XCTAssertEqual(chip.accessibilityLabel, "Recovery day 10 of 14. until 27 Oct. After Harvest Marathon. Easy running only — no hard sessions yet.")
        // It describes now, not the day being browsed.
        XCTAssertNil(today(try snapshot()).trainingDay(on: D.date("2030-10-24")).recovery)

        let czech = try XCTUnwrap(today(try snapshot(), .czech).trainingDay(on: D.asOf).recovery)
        XCTAssertEqual(czech.text, "Regenerace: den 10 z 14 · do 27. 10.")

        let firstWeek = try mutatedRecovery { $0["day"] = 3 }
        XCTAssertEqual(try XCTUnwrap(today(try snapshot(data: firstWeek)).trainingDay(on: D.asOf).recovery).meaningText, "No running this week — walking, mobility and sleep.")
    }

    func testASevenDayWindowNeverCarriesTheTwoWeekText() throws {
        let short = try mutatedRecovery { window in
            window["day"] = 2
            window["of"] = 7
            window["rule"] = "PM-SEQ-3"
            window["until"] = "2030-10-28"
        }
        let chip = try XCTUnwrap(today(try snapshot(data: short)).trainingDay(on: D.asOf).recovery)
        XCTAssertEqual(chip.text, "Recovery day 2 of 7 · until 28 Oct")
        XCTAssertEqual(chip.meaningText, "A week of recovery after a race that ended early.")
        XCTAssertEqual(chip.fraction, 2.0 / 7.0, accuracy: 1e-9)

        let long = try mutatedRecovery { $0["rule"] = "PM-SEQ-3" }
        XCTAssertEqual(try XCTUnwrap(today(try snapshot(data: long)).trainingDay(on: D.asOf).recovery).meaningText, "Easy only — no build for two weeks.")

        let unknown = try mutatedRecovery { window in
            window["rule"] = "PM-SEQ-9"
            window["raceId"] = "not-in-the-season"
            window["until"] = NSNull()
        }
        let bare = try XCTUnwrap(today(try snapshot(data: unknown)).trainingDay(on: D.asOf).recovery)
        XCTAssertEqual(bare.text, "Recovery day 10 of 14", "an unknown rule shows the day count only")
        XCTAssertNil(bare.meaningText)
        XCTAssertNil(bare.raceText)

        let none = try mutatedAthlete { $0["recovery"] = NSNull() }
        XCTAssertNil(today(try snapshot(data: none)).trainingDay(on: D.asOf).recovery)
    }

    func testTheVaultsNoticesAreShownInTheAppsLanguage() throws {
        let minimal = try snapshot(data: try Fixtures.minimal())
        let english = today(minimal).trainingDay(on: D.asOf).vaultNotices
        XCTAssertEqual(english.count, 1)
        XCTAssertTrue(english[0].hasPrefix("No synced activity was found between 2030-09-07 and 2030-10-23"))
        let czech = today(minimal, .czech).trainingDay(on: D.asOf).vaultNotices
        XCTAssertTrue(czech.first?.hasPrefix("Mezi 2030-09-07 a 2030-10-23") ?? false)
        XCTAssertEqual(today(minimal).trainingDay(on: D.date("2030-10-24")).vaultNotices, [], "today only")
        XCTAssertEqual(today(try snapshot()).trainingDay(on: D.asOf).vaultNotices, [])
        // No gate card and no load line without a plan and outside pain mode.
        XCTAssertNil(today(minimal).trainingDay(on: D.asOf).gate)
        XCTAssertNil(today(minimal).trainingDay(on: D.asOf).weekLoad)
        XCTAssertNil(today(minimal).trainingDay(on: D.asOf).recovery)
    }

    // MARK: - Pain during and after a session

    func testTheSessionPainBlock() throws {
        let snap = try snapshot()
        let pain = try XCTUnwrap(plan(snap).sessionDetail(id: "2030-w43-tue-am")?.pain)
        XCTAssertEqual(pain.title, "Pain during and after")
        XCTAssertTrue(pain.isRecorded)
        XCTAssertEqual(pain.recordedLines, [
            "Achilles (left): during 4/10 · after 6/10",
            "Knee (right): during – · after 1/10"
        ])
        XCTAssertEqual(pain.rpe, 7)
        XCTAssertNil(pain.needsRPEText)
        XCTAssertNil(pain.deliveryLine, "the vault's fold, not this phone's event")
        XCTAssertEqual(pain.draft.rows, [
            SessionPainDraftRow(site: .achillesLeft, during: 4, after: 6),
            SessionPainDraftRow(site: .kneeRight, during: 0, after: 1)
        ])

        // Save sends the same RPE again with the pains.
        var draft = pain.draft
        draft.setAfter(4.3, for: .achillesLeft)
        draft.remove(.kneeRight)
        draft.add(.other)
        XCTAssertEqual(pain.payload(draft), SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 7, pains: [
            SessionPainEntry(site: .achillesLeft, during: 4, after: 4.5),
            SessionPainEntry(site: .other, during: 0, after: 0)
        ]))
        XCTAssertEqual(draft.addableSites, [.achillesRight, .kneeLeft, .kneeRight])

        // The vault's session-pain note stays with the session's notes.
        let detail = try XCTUnwrap(plan(snap).sessionDetail(id: "2030-w43-tue-am"))
        XCTAssertTrue(detail.whyLines.last?.hasPrefix("Achilles (left) 4/10 during, 6/10 after this session") ?? false)

        let czech = try XCTUnwrap(plan(snap, .czech).sessionDetail(id: "2030-w43-tue-am")?.pain)
        XCTAssertEqual(czech.recordedLines.last, "Koleno (pravé): během – · po 1/10")
    }

    func testSessionPainNeedsAnRPEAndPainMode() throws {
        // The gym session has no rating yet: the pain is sent with one.
        let unrated = try XCTUnwrap(plan(try snapshot()).sessionDetail(id: "2030-w43-mon-pm")?.pain)
        XCTAssertFalse(unrated.isRecorded)
        XCTAssertEqual(unrated.recordedLines, [])
        XCTAssertNil(unrated.rpe)
        XCTAssertEqual(unrated.needsRPEText, "Choose the effort first — the pain is sent with it.")
        XCTAssertNil(unrated.payload(unrated.draft))
        XCTAssertEqual(unrated.draft.rows.map(\.site), [.achillesLeft, .kneeRight], "the pain episode's sites at 0")
        XCTAssertTrue(unrated.draft.rows.allSatisfy { $0.during == 0 && $0.after == 0 })

        // Rated on the phone: the phone's answer first, with its delivery.
        let rated = logged(.sessionRPE(SessionRPEPayload(date: D.date("2030-10-21"), sessionId: "2030-w43-mon-pm", rpe: 4, pains: [])), seq: 1)
        let mine = try XCTUnwrap(plan(try snapshot([rated])).sessionDetail(id: "2030-w43-mon-pm")?.pain)
        XCTAssertEqual(mine.rpe, 4)
        XCTAssertTrue(mine.isRecorded)
        XCTAssertEqual(mine.recordedLines, ["Pain: nothing hurt"])
        XCTAssertEqual(mine.deliveryLine, "Saved on phone")
        XCTAssertTrue(mine.draft.isEmpty)
        XCTAssertEqual(mine.payload(mine.draft)?.pains, [])

        // Not before the session's day, not outside pain mode, not without
        // a vault connection that can record.
        XCTAssertNil(plan(try snapshot()).sessionDetail(id: "2030-w43-thu-pm")?.pain)
        XCTAssertNil(plan(try snapshot(data: try withoutPainMode())).sessionDetail(id: "2030-w43-tue-am")?.pain)
        XCTAssertNil(plan(try snapshot(recording: false)).sessionDetail(id: "2030-w43-tue-am")?.pain)
    }

    func testTheMorningStepSaysHowYesterdaysPainSettled() throws {
        let step = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(step.settledLines, [
            "Achilles (left) — yesterday after the session: 6/10 → today: 5.5/10",
            "Knee (right) — yesterday after the session: 1/10 → today: 1/10"
        ])
        let czech = try XCTUnwrap(today(try snapshot(), .czech).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(czech.settledLines.first, "Achilovka (levá) — včera po tréninku: 6/10 → dnes: 5,5/10")

        // Both numbers must exist: no morning score, no line.
        let unasked = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 2) { $0["pains"] = NSNull() }
        }
        XCTAssertEqual(try XCTUnwrap(today(try snapshot(data: unasked)).trainingDay(on: D.asOf).checkIn?.pain).settledLines, [])
        // The phone's own answer for yesterday's session comes first.
        let mine = logged(.sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 7, pains: [SessionPainEntry(site: .achillesLeft, during: 2, after: 3)])), seq: 1)
        XCTAssertEqual(try XCTUnwrap(today(try snapshot([mine])).trainingDay(on: D.asOf).checkIn?.pain).settledLines, [
            "Achilles (left) — yesterday after the session: 3/10 → today: 5.5/10"
        ])
        // Outside pain mode the step says nothing of it.
        let healthy = try XCTUnwrap(today(try snapshot(data: try withoutPainMode())).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(healthy.settledLines, [])
    }

    // MARK: - Done without a watch

    func testMarkDoneOffersThePlansDefaults() throws {
        // Today's run has G, A and R; the morning light is amber.
        let model = try XCTUnwrap(plan(try snapshot()).sessionDetail(id: "2030-w43-wed-am")?.manualDone)
        XCTAssertTrue(model.canMark)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.actionTitle, "Mark done (no watch)")
        XCTAssertEqual(model.sheetTitle, "Done without a watch")
        XCTAssertEqual(model.optionCodes, [.g, .a, .r])
        XCTAssertEqual(model.optionNames[.a], "A · Easier")
        XCTAssertEqual(model.initialOption, .a, "the option the morning light points at")
        XCTAssertTrue(model.asksDistance)
        XCTAssertEqual(model.initialKm, 6, "option A's own target")
        XCTAssertNil(model.initialMinutes)

        XCTAssertEqual(
            model.payload(option: .a, minutes: 40, km: 6.04, note: "  flat loop "),
            SessionDonePayload(date: D.asOf, sessionId: "2030-w43-wed-am", option: .a, min: 40, km: 6, note: "flat loop")
        )
        let bare = try XCTUnwrap(model.payload(option: .g, minutes: nil, km: nil, note: ""), "only the day and the session are required")
        XCTAssertEqual(bare.option, .g)
        XCTAssertNil(bare.min)
        XCTAssertNil(bare.km)
        XCTAssertNil(bare.note)
        XCTAssertNil(model.payload(option: .a, minutes: 0, km: 6, note: ""), "minutes are 1-6000")
        XCTAssertNil(model.payload(option: .a, minutes: 40, km: 0, note: ""), "a distance is above 0")

        // Recorded: done on that option at once, on Today too.
        let done = logged(.sessionDone(SessionDonePayload(date: D.asOf, sessionId: "2030-w43-wed-am", option: .a, min: 40, km: 6)), seq: 1)
        let snap = try snapshot([done])
        XCTAssertEqual(snap.session(id: "2030-w43-wed-am")?.session.done?.option, .known(.a))
        let card = today(snap).trainingDay(on: D.asOf).sessions[0]
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.statusText, "Done (logged by hand)")
        XCTAssertEqual(card.options.map(\.highlight), [nil, .done, nil])
        XCTAssertEqual(plan(snap).sessionDetail(id: "2030-w43-wed-am")?.done?.manualLine, "40 min · 6 km")
    }

    func testMarkDoneWorksForAGymSessionAndNotAhead() throws {
        // A missed mobility session: no options, no distance.
        let model = try XCTUnwrap(plan(try snapshot()).sessionDetail(id: "2030-w43-tue-pm")?.manualDone)
        XCTAssertTrue(model.canMark)
        XCTAssertEqual(model.optionCodes, [])
        XCTAssertNil(model.initialOption)
        XCTAssertFalse(model.asksDistance)
        XCTAssertEqual(model.initialMinutes, 20)
        XCTAssertEqual(
            model.payload(option: .g, minutes: 20, km: 3, note: " "),
            SessionDonePayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-pm", option: nil, min: 20, km: nil, note: nil),
            "no option and no distance for a session that has neither"
        )
        // Not for a day ahead, not for a done or skipped session, and not
        // without a vault connection that can record.
        XCTAssertNil(plan(try snapshot()).sessionDetail(id: "2030-w43-thu-pm")?.manualDone)
        XCTAssertNil(plan(try snapshot()).sessionDetail(id: "2030-w43-tue-am")?.manualDone)
        XCTAssertNil(plan(try snapshot(), on: D.date("2030-10-29")).sessionDetail(id: "2030-w44-mon-pm")?.manualDone)
        XCTAssertNil(plan(try snapshot(recording: false)).sessionDetail(id: "2030-w43-tue-pm")?.manualDone)
        // On its own day it is offered.
        XCTAssertEqual(plan(try snapshot(), on: D.date("2030-10-24")).sessionDetail(id: "2030-w43-thu-pm")?.manualDone?.canMark, true)
    }

    // MARK: - The fuel log

    func testTheFuelLogShowsTheVaultsNumbers() throws {
        let fuel = try XCTUnwrap(plan(try snapshot()).sessionDetail(id: "2030-w42-sat-am")?.fuelLog)
        XCTAssertEqual(fuel.title, "Fuel log")
        XCTAssertEqual(fuel.lines, ["90 g carbs eaten · 750 ml fluid", "46 g/h of 60 g/h planned"])
        XCTAssertEqual(fuel.vsPlan, .below)
        XCTAssertEqual(fuel.vsPlanText, "Below plan")
        XCTAssertNil(fuel.hintText)
        XCTAssertEqual(fuel.note, "Two gels and a bar; the third gel stayed in the vest")
        XCTAssertTrue(fuel.canRecord)
        XCTAssertEqual(fuel.actionTitle, "Change the fuel log")
        XCTAssertEqual(fuel.initialCarbs, 90)
        XCTAssertEqual(fuel.initialFluidMl, 750)
        XCTAssertNil(fuel.initialDurationMin, "the vault used the activity's minutes; the phone sent none")
        XCTAssertNil(fuel.deliveryLine)

        XCTAssertEqual(
            fuel.payload(carbs: 90.4, fluidMl: 750, durationMin: nil, note: " "),
            SessionFuelPayload(date: D.date("2030-10-19"), sessionId: "2030-w42-sat-am", carbsG: 90, fluidMl: 750, durationMin: nil, note: nil)
        )
        XCTAssertEqual(fuel.payload(carbs: 0, fluidMl: nil, durationMin: 118, note: "nothing")?.carbsG, 0, "0 g is an answer")
        XCTAssertNil(fuel.payload(carbs: 2500, fluidMl: nil, durationMin: nil, note: ""))
        XCTAssertNil(fuel.payload(carbs: 60, fluidMl: nil, durationMin: 0, note: ""))

        let czech = try XCTUnwrap(plan(try snapshot(), .czech).sessionDetail(id: "2030-w42-sat-am")?.fuelLog)
        XCTAssertEqual(czech.lines, ["90 g sacharidů snědeno · 750 ml tekutin", "46 g/h z plánovaných 60 g/h"])
        XCTAssertEqual(czech.vsPlanText, "Pod plánem")
    }

    func testTheFuelLogIsOfferedForLongRunsAndRaces() throws {
        // Saturday's long run has a fuel plan: offered on its day.
        let saturday = D.date("2030-10-26")
        let long = try XCTUnwrap(plan(try snapshot(), on: saturday).sessionDetail(id: "2030-w43-sat-am")?.fuelLog)
        XCTAssertTrue(long.canRecord)
        XCTAssertEqual(long.lines, [])
        XCTAssertEqual(long.actionTitle, "Log fuel")
        XCTAssertNil(long.vsPlan)
        // The race session, on race day.
        XCTAssertEqual(plan(try snapshot(), on: D.date("2030-11-03")).sessionDetail(id: "2030-w44-sun-am")?.fuelLog?.canRecord, true)
        // Not ahead of its day, and not for a short session.
        XCTAssertNil(plan(try snapshot()).sessionDetail(id: "2030-w43-sat-am")?.fuelLog)
        XCTAssertNil(plan(try snapshot()).sessionDetail(id: "2030-w43-tue-am")?.fuelLog)

        // This phone's log, until the vault has read it.
        let mine = logged(.sessionFuel(SessionFuelPayload(date: saturday, sessionId: "2030-w43-sat-am", carbsG: 120, durationMin: 125, note: "three gels")), seq: 1)
        let pending = try XCTUnwrap(plan(try snapshot([mine]), on: saturday).sessionDetail(id: "2030-w43-sat-am")?.fuelLog)
        XCTAssertEqual(pending.lines, ["120 g carbs eaten"])
        XCTAssertEqual(pending.hintText, "The plan answers after the next sync.")
        XCTAssertEqual(pending.deliveryLine, "Saved on phone")
        XCTAssertEqual(pending.note, "three gels")
        XCTAssertNil(pending.vsPlan, "the verdict is the vault's")
        XCTAssertEqual(pending.initialDurationMin, 125)
        XCTAssertEqual(pending.actionTitle, "Change the fuel log")

        // A log the vault could not put per hour asks for the duration.
        let noDuration = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 1, day: 5, session: 0) { session in
                guard var feedback = session["feedback"] as? [String: Any], var fuel = feedback["fuel"] as? [String: Any] else { return }
                fuel["gPerH"] = NSNull()
                fuel["durationMin"] = NSNull()
                fuel["vsPlan"] = NSNull()
                feedback["fuel"] = fuel
                session["feedback"] = feedback
            }
        }
        let unknown = try XCTUnwrap(plan(try snapshot(data: noDuration)).sessionDetail(id: "2030-w42-sat-am")?.fuelLog)
        XCTAssertEqual(unknown.lines, ["90 g carbs eaten · 750 ml fluid"])
        XCTAssertEqual(unknown.hintText, "Add the duration to see grams per hour.")
        XCTAssertNil(unknown.vsPlanText)
    }

    // MARK: - Race results

    func testTheOrganisersTimeIsTheResultAndTheElapsedTimeTheSecondLine() throws {
        let builder = plan(try snapshot())
        let lakeside = try XCTUnwrap(builder.raceDetail(id: "lakeside-10k-2030")?.result)
        XCTAssertEqual(lakeside.title, "Result")
        XCTAssertTrue(lakeside.hasRecord)
        XCTAssertEqual(lakeside.statusText, "Finished")
        XCTAssertEqual(lakeside.timeText, "0:45:41", "the organiser's time first")
        XCTAssertEqual(lakeside.elapsedText, "0:46:03 elapsed")
        XCTAssertEqual(lakeside.factLines, ["10 km"])
        XCTAssertNil(lakeside.goalReachedText, "not reached is not shown")
        XCTAssertEqual(lakeside.personalRecordText, "Personal record")
        XCTAssertEqual(lakeside.sourceText, "From the race report")
        XCTAssertNil(lakeside.reasonText)
        XCTAssertNil(lakeside.editor, "the report states the result: nothing to record")
        XCTAssertEqual(lakeside.withdrawEventIDs, [])

        let marathon = try XCTUnwrap(builder.raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertEqual(marathon.statusText, "Finished")
        XCTAssertEqual(marathon.timeText, "3:24:10", "one time: the elapsed one is the result")
        XCTAssertNil(marathon.elapsedText, "and there is no second line")
        XCTAssertEqual(marathon.factLines, ["42.2 km"])
        XCTAssertEqual(marathon.goalReachedText, "Goal reached")
        XCTAssertNil(marathon.personalRecordText, "not known")
        XCTAssertEqual(marathon.sourceText, "Logged in the app")
        XCTAssertEqual(marathon.note, "Even pace, strong last 5 km")
        XCTAssertEqual(marathon.actionTitle, "Change the result")
        let editor = try XCTUnwrap(marathon.editor)
        XCTAssertEqual(editor.statuses, [.finished, .dnf, .dns])
        XCTAssertEqual(editor.initialStatus, .finished)
        XCTAssertEqual(editor.initialTime, "3:24:10")
        XCTAssertEqual(editor.initialOfficialTime, "")
        XCTAssertEqual(editor.initialDistanceKm, 42.2)
        XCTAssertFalse(editor.asksLaps)
        XCTAssertNil(editor.beforeRaceText)

        let czech = try XCTUnwrap(plan(try snapshot(), .czech).raceDetail(id: "lakeside-10k-2030")?.result)
        XCTAssertEqual(czech.statusText, "Dokončeno")
        XCTAssertEqual(czech.elapsedText, "0:46:03 celkový čas")
        XCTAssertEqual(czech.personalRecordText, "Osobní rekord")
    }

    func testANeutralStatusWithItsReasonAndLaps() throws {
        let stopped = try mutatedRace("harvest-marathon-2030") { race in
            race["result"] = [
                "status": "dnf", "reason": "stop-rule", "time": "14:02:10", "officialTime": NSNull(), "distanceKm": 61.5,
                "laps": 6, "goalReached": false, "pr": NSNull(), "reportPath": NSNull(), "source": "event", "note": NSNull()
            ] as [String: Any]
        }
        let result = try XCTUnwrap(plan(try snapshot(data: stopped)).raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertEqual(result.status, .dnf)
        XCTAssertEqual(result.statusText, "Did not finish")
        XCTAssertEqual(result.reasonText, "Stopped by the stop rule")
        XCTAssertEqual(result.timeText, "14:02:10")
        XCTAssertEqual(result.factLines, ["61.5 km", "6 laps"])
        XCTAssertNil(result.goalReachedText)
        XCTAssertEqual(result.editor?.asksLaps, true, "laps are recorded: a lap race")
        XCTAssertEqual(result.editor?.initialReason, .stopRule)
        let czech = try XCTUnwrap(plan(try snapshot(data: stopped), .czech).raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertEqual(czech.statusText, "Nedokončeno")
        XCTAssertEqual(czech.factLines.last, "6 kol")

        let notStarted = try mutatedRace("harvest-marathon-2030") { race in
            race["result"] = ["status": "dns", "reason": "weather", "source": "event"] as [String: Any]
        }
        let dns = try XCTUnwrap(plan(try snapshot(data: notStarted)).raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertEqual(dns.statusText, "Did not start")
        XCTAssertEqual(dns.reasonText, "Other reason", "a reason this build does not know reads as other")
        XCTAssertNil(dns.timeText)
        XCTAssertEqual(dns.factLines, [])
    }

    func testTheResultSheetOnAndBeforeRaceDay() throws {
        let snap = try snapshot()
        // Eleven days before: only a non-start, inside the two weeks.
        let before = try XCTUnwrap(plan(snap).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertFalse(before.hasRecord)
        XCTAssertEqual(before.actionTitle, "Did not start")
        let early = try XCTUnwrap(before.editor)
        XCTAssertEqual(early.statuses, [.dns])
        XCTAssertEqual(early.initialStatus, .dns)
        XCTAssertEqual(early.beforeRaceText, "Before race day only a non-start can be recorded.")
        XCTAssertNil(early.payload(status: .finished, reason: nil, time: "3:05:00", officialTime: "", distanceKm: 30, laps: nil, note: ""), "a finish is not offered before race day")
        XCTAssertEqual(
            early.payload(status: .dns, reason: .illness, time: "3:05:00", officialTime: "", distanceKm: 30, laps: nil, note: " flu "),
            RaceResultPayload(raceId: "valley-30k-2030", status: .dns, reason: .illness, time: nil, officialTime: nil, distanceKm: nil, laps: nil, note: "flu"),
            "a race not started has no time and no distance"
        )
        // Further ahead there is nothing to show and nothing to record.
        XCTAssertNil(plan(snap, on: D.date("2030-10-01")).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertNil(plan(snap).raceDetail(id: "ridge-ultra-2031")?.result, "an approximate date months ahead")
        // Nor without a vault connection that can record.
        XCTAssertNil(plan(try snapshot(recording: false)).raceDetail(id: "valley-30k-2030")?.result)

        // Race day: all three, starting from the race's own distance.
        let raceDay = try XCTUnwrap(plan(snap, on: D.date("2030-11-03")).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertEqual(raceDay.actionTitle, "How did it go?")
        let editor = try XCTUnwrap(raceDay.editor)
        XCTAssertEqual(editor.statuses, [.finished, .dnf, .dns])
        XCTAssertEqual(editor.statusName(.finished), "Finished")
        XCTAssertEqual(editor.reasons, [.stopRule, .injury, .illness, .other])
        XCTAssertEqual(editor.reasonName(.stopRule), "Stopped by the stop rule")
        XCTAssertEqual(editor.initialDistanceKm, 30)
        XCTAssertEqual(editor.initialTime, "")
        XCTAssertFalse(editor.asksReason(.finished))
        XCTAssertTrue(editor.asksReason(.dnf))
        XCTAssertFalse(editor.asksTimes(.dns))

        XCTAssertEqual(
            editor.payload(status: .finished, reason: .injury, time: "03:05:09", officialTime: " 3:05:09 ", distanceKm: 30.2049, laps: 4, note: ""),
            RaceResultPayload(raceId: "valley-30k-2030", status: .finished, reason: nil, time: "3:05:09", officialTime: nil, distanceKm: 30.2, laps: nil, note: nil),
            "no reason for a finish, never a copy of the elapsed time, no laps for a race without them"
        )
        XCTAssertEqual(
            editor.payload(status: .dnf, reason: .stopRule, time: "2:10:00", officialTime: "", distanceKm: 19, laps: nil, note: "pain 6 at the second aid")?.reason,
            .stopRule
        )
        XCTAssertNil(editor.payload(status: .finished, reason: nil, time: "3h05", officialTime: "", distanceKm: 30, laps: nil, note: ""))
        XCTAssertNil(editor.payload(status: .finished, reason: nil, time: "3:05", officialTime: "", distanceKm: 30, laps: nil, note: ""))
        XCTAssertNil(editor.payload(status: .finished, reason: nil, time: "3:05:09", officialTime: "soon", distanceKm: 30, laps: nil, note: ""))
        XCTAssertNil(editor.payload(status: .finished, reason: nil, time: "3:05:09", officialTime: "", distanceKm: 0, laps: nil, note: ""))
        XCTAssertNotNil(editor.payload(status: .finished, reason: nil, time: "", officialTime: "", distanceKm: nil, laps: nil, note: ""), "only the race and the status are required")
        XCTAssertEqual(RaceResultEditorModel.cleanTime(" 0:46:03 "), "0:46:03")
        XCTAssertEqual(RaceResultEditorModel.cleanTime("021:31:23"), "21:31:23")
        XCTAssertNil(RaceResultEditorModel.cleanTime("  "))
    }

    func testALapRaceSendsBothTimesAndItsLaps() throws {
        let timed = try mutatedRace("valley-30k-2030") { $0["distanceLabel"] = "24h" }
        let editor = try XCTUnwrap(plan(try snapshot(data: timed), on: D.date("2030-11-04")).raceDetail(id: "valley-30k-2030")?.result?.editor)
        XCTAssertTrue(editor.asksLaps)
        XCTAssertEqual(
            editor.payload(status: .finished, reason: nil, time: "21:31:23", officialTime: "19:57:19", distanceKm: nil, laps: 9, note: ""),
            RaceResultPayload(raceId: "valley-30k-2030", status: .finished, reason: nil, time: "21:31:23", officialTime: "19:57:19", distanceKm: nil, laps: 9, note: nil)
        )
    }

    func testThisPhonesResultUntilTheVaultHasReadItAndARefusal() throws {
        let raceDay = D.date("2030-11-03")
        let sent = RaceResultPayload(raceId: "valley-30k-2030", status: .dnf, reason: .stopRule, time: "2:10:00", distanceKm: 19)
        let mine = logged(.raceResult(sent), seq: 1)

        let pending = try XCTUnwrap(plan(try snapshot([mine]), on: raceDay).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertTrue(pending.hasRecord)
        XCTAssertEqual(pending.statusText, "Did not finish")
        XCTAssertEqual(pending.reasonText, "Stopped by the stop rule")
        XCTAssertEqual(pending.timeText, "2:10:00")
        XCTAssertEqual(pending.factLines, ["19 km"])
        XCTAssertEqual(pending.deliveryLine, "Saved on phone")
        XCTAssertEqual(pending.pendingHint, "The plan answers after the next sync.")
        XCTAssertNil(pending.sourceText, "not the vault's record yet")
        XCTAssertNil(pending.goalReachedText)
        XCTAssertEqual(pending.actionTitle, "Change the result")
        XCTAssertEqual(pending.withdrawEventIDs, ["id-1"])
        XCTAssertEqual(pending.withdrawTitle, "Withdraw this result")
        XCTAssertEqual(pending.editor?.initialStatus, .dnf)
        XCTAssertEqual(pending.editor?.initialTime, "2:10:00")

        // Read by the vault and not in the file: the file's word (nothing).
        let read = try XCTUnwrap(plan(try snapshot([mine], acked: 1), on: raceDay).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertFalse(read.hasRecord)
        XCTAssertNil(read.deliveryLine)
        XCTAssertEqual(read.withdrawEventIDs, ["id-1"])

        // Sent before race day and refused: the vault's reason is shown.
        let refusal = PlanOutcome(
            event: "id-1", deviceId: device, seq: 1, type: "race.result", week: nil, sessionId: nil,
            status: .known(.refused),
            reason: LocalizedText(values: ["en": "The race is on 2030-11-03: a result before race day is not taken.", "cz": "Závod je 2030-11-03: výsledek před dnem závodu se nepřijímá."])
        )
        let refused = try XCTUnwrap(plan(try snapshot([mine], acked: 1, outcomes: [refusal])).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertEqual(refused.refusalText, "The race is on 2030-11-03: a result before race day is not taken.")
        XCTAssertFalse(refused.hasRecord, "a refused result is not the result")
        let czech = try XCTUnwrap(plan(try snapshot([mine], acked: 1, outcomes: [refusal]), .czech).raceDetail(id: "valley-30k-2030")?.result)
        XCTAssertEqual(czech.refusalText, "Závod je 2030-11-03: výsledek před dnem závodu se nepřijímá.")
        let silent = PlanOutcome(event: "id-1", deviceId: device, seq: 1, type: "race.result", week: nil, sessionId: nil, status: .known(.refused), reason: nil)
        XCTAssertEqual(plan(try snapshot([mine], acked: 1, outcomes: [silent])).raceDetail(id: "valley-30k-2030")?.result?.refusalText, "The vault did not accept this result.")
    }

    func testWithdrawingAResultHidesItUntilTheVaultAnswers() throws {
        let sent = logged(.raceResult(RaceResultPayload(raceId: "harvest-marathon-2030", status: .finished, time: "3:24:10", distanceKm: 42.2)), seq: 1)
        let withdraw = logged(.eventRetracted(EventRetractedPayload(target: "id-1")), seq: 2)

        let waiting = try XCTUnwrap(plan(try snapshot([sent, withdraw], acked: 1)).raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertFalse(waiting.hasRecord, "the app's result on file is on its way out")
        XCTAssertEqual(waiting.pendingHint, "The plan answers after the next sync.")
        XCTAssertEqual(waiting.withdrawEventIDs, [])
        XCTAssertEqual(waiting.actionTitle, "How did it go?")

        let answered = try XCTUnwrap(plan(try snapshot([sent, withdraw], acked: 2)).raceDetail(id: "harvest-marathon-2030")?.result)
        XCTAssertTrue(answered.hasRecord, "an old file still shows it; the next one will not")
        XCTAssertNil(answered.pendingHint)
    }

    // MARK: - Rewards read the vault's result

    func testTheRewardFactsComeFromTheRealResult() throws {
        let data = try Fixtures.example()
        let extras = ProjectionRewardExtras.decode(data)
        XCTAssertEqual(extras.raceResults, [
            "lakeside-10k-2030": ProjectionRewardExtras.RaceResult(outcome: .known(.finished), goalReached: false, pr: true),
            "harvest-marathon-2030": ProjectionRewardExtras.RaceResult(outcome: .known(.finished), goalReached: true, pr: nil)
        ])
        XCTAssertEqual(extras.gateDate, D.asOf)
        XCTAssertEqual(extras.weekLoads["2030-W42"], ProjectionRewardExtras.WeekLoad(unplannedRunKm: 6, overPlanKm: 5.1))

        let facts = TrainingPlanFacts.build(snapshot: try snapshot(), extras: extras, today: D.asOf)
        let byID = Dictionary(uniqueKeysWithValues: facts.races.map { ($0.id, $0) })
        XCTAssertEqual(byID["harvest-marathon-2030"]?.outcome, .finished)
        XCTAssertEqual(byID["harvest-marathon-2030"]?.goalReached, true)
        XCTAssertNil(byID["harvest-marathon-2030"]?.isPersonalRecord, "not known is not no")
        XCTAssertNil(byID["harvest-marathon-2030"]?.stoppedByRule)
        XCTAssertEqual(byID["lakeside-10k-2030"]?.isPersonalRecord, true)
        XCTAssertEqual(byID["lakeside-10k-2030"]?.goalReached, false)
        XCTAssertNil(byID["valley-30k-2030"]?.outcome, "no result yet")
        XCTAssertNil(byID["valley-30k-2030"]?.fuelPlanFollowed)
        // Building twice gives the same facts: a reward keyed by its race
        // is granted once.
        XCTAssertEqual(TrainingPlanFacts.build(snapshot: try snapshot(), extras: extras, today: D.asOf), facts)

        // This phone's own unread result releases nothing.
        let mine = logged(.raceResult(RaceResultPayload(raceId: "valley-30k-2030", status: .finished, time: "3:05:00")), seq: 1)
        let optimistic = TrainingPlanFacts.build(snapshot: try snapshot([mine]), extras: extras, today: D.date("2030-11-03"))
        XCTAssertNil(optimistic.races.first { $0.id == "valley-30k-2030" }?.outcome)
    }

    func testAStopRuleReasonIsAWiseCallAndTheFuelLogSaysWhetherThePlanWasFollowed() throws {
        func extras(_ result: String) -> ProjectionRewardExtras.RaceResult? {
            let json = #"{ "season": { "races": [ { "id": "r", "result": \#(result) } ] } }"#
            return ProjectionRewardExtras.decode(Data(json.utf8)).raceResults["r"]
        }
        XCTAssertEqual(
            extras(#"{ "status": "dnf", "reason": "stop-rule", "goalReached": null, "pr": null }"#),
            ProjectionRewardExtras.RaceResult(outcome: .known(.dnf), stopRule: true)
        )
        XCTAssertEqual(extras(#"{ "status": "dns", "reason": "injury" }"#)?.stopRule, false)
        XCTAssertNil(extras(#"{ "status": "finished", "reason": null }"#)?.stopRule)
        XCTAssertEqual(extras(#"{ "status": "paused" }"#)?.outcome, .unknown("paused"))
        XCTAssertNil(extras("null"))

        func raceFuel(_ verdict: Any) throws -> Bool? {
            let data = try Fixtures.mutatedExample { object in
                try Fixtures.mutateSession(&object, week: 3, day: 6, session: 0) { session in
                    session["feedback"] = [
                        "rpe": NSNull(), "feel": NSNull(), "note": NSNull(), "pains": NSNull(),
                        "fuel": ["carbsG": 210, "fluidMl": NSNull(), "durationMin": 185, "gPerH": 68, "planGPerH": 70, "vsPlan": verdict, "note": NSNull()] as [String: Any]
                    ] as [String: Any]
                }
            }
            let facts = TrainingPlanFacts.build(snapshot: try snapshot(data: data), extras: ProjectionRewardExtras.decode(data), today: D.date("2030-11-04"))
            return facts.races.first { $0.id == "valley-30k-2030" }?.fuelPlanFollowed
        }
        XCTAssertEqual(try raceFuel("on"), true)
        XCTAssertEqual(try raceFuel("below"), false)
        XCTAssertEqual(try raceFuel("above"), false)
        XCTAssertNil(try raceFuel(NSNull()), "no verdict is not known")
        XCTAssertNil(try raceFuel("sideways"), "a verdict this build does not know")
    }
}
