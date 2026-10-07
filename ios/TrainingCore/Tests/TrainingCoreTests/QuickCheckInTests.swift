// QuickCheckInTests.swift
//
// add-training-shortcuts-and-widgets (design D3): the check-in the
// Controls, the Home Screen widget and the "Morning check-in" App Shortcut
// record. The light alone leaves `pains` nil (the day's earlier answer is
// kept); one pain number becomes one entry -- within 0...10 or refused, on
// the half-step grid, for the given site or the first site Today's pain
// step would offer.
//
// On the vault's example fixture: 02:05Z on 2030-10-23 is 04:05 in Prague,
// after the 03:00 day boundary, so the training day is the 23rd and its
// traffic-light session is `2030-w43-wed-am`. No day before the 23rd has a
// pain answer in the file. Everything is synthetic.

import XCTest
@testable import TrainingCore

final class QuickCheckInTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let morning = Date(timeIntervalSince1970: 1_918_951_500)
    private let wednesday = D.date("2030-10-23")
    private let tuesday = D.date("2030-10-22")

    private func projection(_ data: Data? = nil) throws -> Projection {
        guard let data else { return try Fixtures.exampleProjection().projection }
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return decoded.projection
    }

    private func checkIn(_ light: MorningLight, pain: QuickPainAnswer?, projection: Projection?, checkIns: CheckInOverlay = .empty) throws -> MorningCheckInPayload {
        try CheckInPlanning.morningCheckIn(light: light, pain: pain, projection: projection, checkIns: checkIns, now: morning, deviceTimeZone: utc)
    }

    // MARK: The score

    func testAScoreIsRoundedToTheNearestHalfStep() throws {
        XCTAssertEqual(try CheckInPlanning.painScore(0), 0)
        XCTAssertEqual(try CheckInPlanning.painScore(10), 10)
        XCTAssertEqual(try CheckInPlanning.painScore(3), 3)
        XCTAssertEqual(try CheckInPlanning.painScore(5.5), 5.5)
        XCTAssertEqual(try CheckInPlanning.painScore(4.3), 4.5)
        XCTAssertEqual(try CheckInPlanning.painScore(4.2), 4)
        XCTAssertEqual(try CheckInPlanning.painScore(0.2), 0)
        XCTAssertEqual(try CheckInPlanning.painScore(9.8), 10)
    }

    func testAScoreOutsideZeroToTenIsRefusedNotClamped() {
        for refused in [-0.5, 10.5, 12, -3, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try CheckInPlanning.painScore(refused), "\(refused) must be refused") { error in
                XCTAssertEqual(error as? QuickCheckInError, .painScoreOutOfRange)
            }
        }
    }

    // MARK: The light alone (Controls, the widget, "Amber in ...")

    func testWithoutAScoreTheCheckInCarriesNoPainAnswer() throws {
        let example = try projection()
        let payload = try checkIn(.amberLight, pain: nil, projection: example)

        XCTAssertEqual(payload, MorningCheckInPayload(date: wednesday, light: .amberLight, sessionId: "2030-w43-wed-am"))
        XCTAssertNil(payload.pains, "not asked: the vault keeps the day's earlier answer")
        XCTAssertEqual(
            payload,
            CheckInPlanning.morningCheckIn(light: .amberLight, projection: example, now: morning, deviceTimeZone: utc),
            "exactly the Controls' check-in"
        )
    }

    // MARK: One pain number

    func testAScoreWithoutASiteGoesToTheFallbackSiteWhenNothingWasScoredBefore() throws {
        let payload = try checkIn(.greenLight, pain: QuickPainAnswer(score: 3), projection: try projection())

        XCTAssertEqual(payload.date, wednesday)
        XCTAssertEqual(payload.light, .greenLight)
        XCTAssertEqual(payload.sessionId, "2030-w43-wed-am")
        XCTAssertEqual(payload.option, MorningLight.greenLight.option)
        XCTAssertEqual(payload.pains, [PainEntry(site: .achillesLeft, score: 3)])
        XCTAssertNoThrow(try HubEventPayload.morningCheckIn(payload).validate(), "what is built is what may be written")
    }

    func testAScoreWithoutASiteGoesToTheSiteScoredLast() throws {
        // The file's Tuesday scored the right Achilles (and a knee).
        let right: [[String: Any]] = [["site": "knee-left", "score": 2], ["site": "achilles-right", "score": 0]]
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 1) { $0["pains"] = right }
        }
        let payload = try checkIn(.amberLight, pain: QuickPainAnswer(score: 2), projection: try projection(data))

        XCTAssertEqual(payload.pains, [PainEntry(site: .achillesRight, score: 2)])
    }

    func testThePhonesOwnEarlierAnswerCountsForTheDefaultSite() throws {
        // Nothing in the file, but this phone scored the right Achilles on
        // Tuesday (not delivered yet).
        let earlier = LoggedEvent(
            event: HubEvent(
                id: "id-1",
                deviceId: "ios-0000beef",
                seq: 1,
                at: "t",
                payload: .morningCheckIn(MorningCheckInPayload(date: tuesday, light: .greenLight, sessionId: nil, pains: [PainEntry(site: .achillesRight, score: 1)]))
            ),
            recordedAt: morning.addingTimeInterval(-86_400)
        )
        let overlay = CheckInOverlay.fold([earlier], unsentSegments: [])
        let example = try projection()

        let withOverlay = try checkIn(.greenLight, pain: QuickPainAnswer(score: 1.5), projection: example, checkIns: overlay)
        XCTAssertEqual(withOverlay.pains, [PainEntry(site: .achillesRight, score: 1.5)])

        let without = try checkIn(.greenLight, pain: QuickPainAnswer(score: 1.5), projection: example)
        XCTAssertEqual(without.pains, [PainEntry(site: .achillesLeft, score: 1.5)], "without the overlay the file knows no earlier answer")
    }

    func testAGivenSiteWins() throws {
        let payload = try checkIn(.redLight, pain: QuickPainAnswer(score: 6, site: .kneeLeft), projection: try projection())
        XCTAssertEqual(payload.pains, [PainEntry(site: .kneeLeft, score: 6)])
        XCTAssertEqual(payload.light, .redLight)
    }

    func testZeroIsAnAnswer() throws {
        let payload = try checkIn(.greenLight, pain: QuickPainAnswer(score: 0), projection: try projection())
        XCTAssertEqual(payload.pains, [PainEntry(site: .achillesLeft, score: 0)], "0 is sent: a morning without an entry is never counted as 0")
    }

    func testAHalfStepIsRecordedOnTheGrid() throws {
        let payload = try checkIn(.amberLight, pain: QuickPainAnswer(score: 4.3), projection: try projection())
        XCTAssertEqual(payload.pains?.map(\.score), [4.5])
        XCTAssertNoThrow(try HubEventPayload.morningCheckIn(payload).validate())
    }

    func testAnOutOfRangeScoreRefusesTheWholeCheckIn() throws {
        let example = try projection()
        XCTAssertThrowsError(try checkIn(.amberLight, pain: QuickPainAnswer(score: 12), projection: example)) { error in
            XCTAssertEqual(error as? QuickCheckInError, .painScoreOutOfRange)
        }
        XCTAssertThrowsError(try checkIn(.amberLight, pain: QuickPainAnswer(score: -1, site: .kneeRight), projection: example)) { error in
            XCTAssertEqual(error as? QuickCheckInError, .painScoreOutOfRange)
        }
    }

    func testWithoutAPlanTheCheckInStillHasADayAndTheFallbackSite() throws {
        let payload = try checkIn(.redLight, pain: QuickPainAnswer(score: 2), projection: nil)

        XCTAssertEqual(payload.date, wednesday, "the device's zone and the default day boundary")
        XCTAssertNil(payload.sessionId)
        XCTAssertNil(payload.option)
        XCTAssertEqual(payload.pains, [PainEntry(site: PainDraft.fallbackSites[0], score: 2)])
    }

    // MARK: The pains rule by itself

    func testPainsForAnAnswerOnGivenDays() throws {
        XCTAssertNil(try CheckInPlanning.pains(for: nil, on: wednesday, days: []))
        XCTAssertEqual(
            try CheckInPlanning.pains(for: QuickPainAnswer(score: 1), on: wednesday, days: []),
            [PainEntry(site: .achillesLeft, score: 1)]
        )
        XCTAssertEqual(
            try CheckInPlanning.pains(for: QuickPainAnswer(score: 1, site: .other), on: wednesday, days: []),
            [PainEntry(site: .other, score: 1)],
            "no note is sent: a shortcut has none to give"
        )
    }

    // MARK: A repeated check-in

    /// This phone's own events, folded; each a check-in recorded ten
    /// minutes apart before `morning`, oldest first, none delivered yet.
    private func overlay(_ payloads: MorningCheckInPayload...) -> CheckInOverlay {
        let events = payloads.enumerated().map { index, payload in
            LoggedEvent(
                event: HubEvent(id: "id-\(index + 1)", deviceId: "ios-0000beef", seq: index + 1, at: "t", payload: .morningCheckIn(payload)),
                recordedAt: morning.addingTimeInterval(Double(index - payloads.count) * 600)
            )
        }
        return CheckInOverlay.fold(events, unsentSegments: [])
    }

    private func decide(_ light: MorningLight, pain: QuickPainAnswer? = nil, projection: Projection?, checkIns: CheckInOverlay) throws -> QuickCheckInDecision {
        try CheckInPlanning.quickCheckIn(light: light, pain: pain, projection: projection, checkIns: checkIns, now: morning, deviceTimeZone: utc)
    }

    /// Amber for the example's Wednesday, with an option that is NOT
    /// amber's own letter: what a second tap must not overwrite.
    private var amberWithAChosenOption: MorningCheckInPayload {
        MorningCheckInPayload(date: wednesday, light: .amberLight, sessionId: "2030-w43-wed-am", option: .r)
    }

    func testTheSameLightAgainRecordsNothing() throws {
        let example = try projection()

        XCTAssertEqual(
            try decide(.amberLight, projection: example, checkIns: overlay(amberWithAChosenOption)),
            .alreadyRecorded(date: wednesday, light: .amberLight),
            "a second tap would replace the chosen option with amber's default"
        )
        let plain = MorningCheckInPayload(date: wednesday, light: .greenLight, sessionId: "2030-w43-wed-am")
        XCTAssertEqual(
            try decide(.greenLight, projection: example, checkIns: overlay(plain)),
            .alreadyRecorded(date: wednesday, light: .greenLight),
            "two taps are one check-in"
        )
    }

    func testTheSameLightWithAScoreKeepsTheEarlierSessionAndOption() throws {
        let example = try projection()

        let decision = try decide(.amberLight, pain: QuickPainAnswer(score: 2), projection: example, checkIns: overlay(amberWithAChosenOption))
        var expected = amberWithAChosenOption
        expected.pains = [PainEntry(site: .achillesLeft, score: 2)]
        XCTAssertEqual(decision, .record(expected), "only the pain is new")

        // An earlier check-in that named no session keeps none, even
        // though today's plan has one.
        let noSession = MorningCheckInPayload(date: wednesday, light: .amberLight, sessionId: nil)
        let kept = try decide(.amberLight, pain: QuickPainAnswer(score: 0.5, site: .kneeRight), projection: example, checkIns: overlay(noSession))
        XCTAssertEqual(
            kept,
            .record(MorningCheckInPayload(date: wednesday, light: .amberLight, sessionId: nil, option: nil, pains: [PainEntry(site: .kneeRight, score: 0.5)]))
        )
    }

    func testAnotherLightIsANewChoiceWithItsOwnOption() throws {
        let example = try projection()

        XCTAssertEqual(
            try decide(.greenLight, projection: example, checkIns: overlay(amberWithAChosenOption)),
            .record(MorningCheckInPayload(date: wednesday, light: .greenLight, sessionId: "2030-w43-wed-am")),
            "a changed light is a new check-in: today's session, green's own option, no pain answer"
        )
        let withScore = try decide(.redLight, pain: QuickPainAnswer(score: 6), projection: example, checkIns: overlay(amberWithAChosenOption))
        XCTAssertEqual(
            withScore,
            .record(MorningCheckInPayload(date: wednesday, light: .redLight, sessionId: "2030-w43-wed-am", pains: [PainEntry(site: .achillesLeft, score: 6)]))
        )
    }

    func testWithoutAnEarlierCheckInItIsRecordedAsBefore() throws {
        let example = try projection()
        let asBefore = CheckInPlanning.morningCheckIn(light: .amberLight, projection: example, now: morning, deviceTimeZone: utc)

        XCTAssertEqual(try decide(.amberLight, projection: example, checkIns: .empty), .record(asBefore))
        // Yesterday's amber is not today's.
        let yesterday = MorningCheckInPayload(date: tuesday, light: .amberLight, sessionId: nil)
        XCTAssertEqual(try decide(.amberLight, projection: example, checkIns: overlay(yesterday)), .record(asBefore))
        // No plan at all: still a day, and still a repeat the second time.
        let bare = MorningCheckInPayload(date: wednesday, light: .redLight, sessionId: nil)
        XCTAssertEqual(try decide(.redLight, projection: nil, checkIns: .empty), .record(bare))
        XCTAssertEqual(try decide(.redLight, projection: nil, checkIns: overlay(bare)), .alreadyRecorded(date: wednesday, light: .redLight))
    }

    func testARefusedScoreRecordsNothingEvenOnARepeat() throws {
        let example = try projection()
        XCTAssertThrowsError(try decide(.amberLight, pain: QuickPainAnswer(score: 12), projection: example, checkIns: overlay(amberWithAChosenOption))) { error in
            XCTAssertEqual(error as? QuickCheckInError, .painScoreOutOfRange)
        }
    }

    func testTheOverlayHoldsTheLatestCheckInOfADay() {
        XCTAssertNil(CheckInOverlay.empty.checkIn(on: wednesday))
        XCTAssertEqual(
            overlay(amberWithAChosenOption).checkIn(on: wednesday),
            RecordedCheckIn(light: .amberLight, sessionId: "2030-w43-wed-am", option: .r)
        )
        // Latest wins for the light, the session and the option together.
        let later = MorningCheckInPayload(date: wednesday, light: .greenLight, sessionId: nil)
        XCTAssertEqual(
            overlay(amberWithAChosenOption, later).checkIn(on: wednesday),
            RecordedCheckIn(light: .greenLight, sessionId: nil, option: nil)
        )
        XCTAssertNil(overlay(amberWithAChosenOption).checkIn(on: tuesday))
    }

    // MARK: A site needs a score

    func testASiteWithoutAScoreIsRefusedNotDropped() throws {
        XCTAssertNil(try QuickPainAnswer.given(score: nil, site: nil), "nothing said about pain")
        XCTAssertEqual(try QuickPainAnswer.given(score: 2, site: nil), QuickPainAnswer(score: 2))
        XCTAssertEqual(try QuickPainAnswer.given(score: 2, site: .kneeLeft), QuickPainAnswer(score: 2, site: .kneeLeft))
        XCTAssertThrowsError(try QuickPainAnswer.given(score: nil, site: .kneeLeft)) { error in
            XCTAssertEqual(error as? QuickCheckInError, .painSiteWithoutScore)
        }
    }

    func testAScoreOutOfRangeIsStillTheScoresOwnRefusal() throws {
        // `given` only pairs the two; the range is checked when the
        // check-in is built.
        let answer = try QuickPainAnswer.given(score: 12, site: .kneeLeft)
        XCTAssertThrowsError(try checkIn(.amberLight, pain: answer, projection: nil)) { error in
            XCTAssertEqual(error as? QuickCheckInError, .painScoreOutOfRange)
        }
    }
}
