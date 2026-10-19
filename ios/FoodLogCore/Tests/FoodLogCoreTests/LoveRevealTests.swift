// LoveRevealTests.swift
//
// add-partner-love-theme D6, spec love-messages "A message is revealed
// only once its time has come": no text before the minute, revealed at it
// or on opening the notification, and a week away caught up on return.
// Also the hearts ledger and coupons (spec partner-achievements).

import XCTest
@testable import FoodLogCore

final class LoveRevealTests: XCTestCase {
    private typealias Support = LoveTestSupport
    private let calendar = LoveTestSupport.prague

    private func minute(_ pack: LovePack, _ day: String) -> Int {
        LoveMinute.minute(seed: pack.seed, day: day, otherReminderMinutes: [])
    }

    func testBeforeTheMinuteOnlyTheArrivalIsKnown() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let early = Support.date("2030-03-14", 7, 30, calendar: calendar)

        let result = LoveReveal.reveal(day: "2030-03-14", pack: pack, state: &state, now: early, calendar: calendar)

        guard case .arrives(let at) = result else { return XCTFail("revealed early: \(result)") }
        XCTAssertEqual(at, LoveDay.date(day: "2030-03-14", minute: minute(pack, "2030-03-14"), calendar: calendar))
        XCTAssertTrue(state.revealed.isEmpty)
    }

    func testAtTheMinuteTheMessageIsRevealedAndKept() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let due = LoveDay.date(day: "2030-03-14", minute: minute(pack, "2030-03-14"), calendar: calendar)!

        let result = LoveReveal.reveal(day: "2030-03-14", pack: pack, state: &state, now: due, calendar: calendar)

        guard case .revealed(let message) = result else { return XCTFail("not revealed: \(result)") }
        XCTAssertEqual(message.day, "2030-03-14")
        XCTAssertEqual(pack.daily(id: message.messageId)?.text, message.text)
        XCTAssertEqual(state.revealed["2030-03-14"], message)
        XCTAssertEqual(LoveReveal.state(day: "2030-03-14", pack: pack, state: state, now: due, calendar: calendar), .revealed(message))
    }

    func testOpeningTheNotificationRevealsEarly() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let early = Support.date("2030-03-14", 7, 59, calendar: calendar)

        let result = LoveReveal.reveal(day: "2030-03-14", pack: pack, state: &state, now: early, openedFromNotification: true, calendar: calendar)

        guard case .revealed = result else { return XCTFail("not revealed: \(result)") }
    }

    func testAFutureDayIsNeverRevealed() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let now = Support.date("2030-03-14", 12, 59, calendar: calendar)

        let result = LoveReveal.reveal(day: "2030-03-15", pack: pack, state: &state, now: now, openedFromNotification: true, calendar: calendar)

        XCTAssertEqual(result, .none)
        XCTAssertNil(state.revealed["2030-03-15"])
    }

    func testAWeekAwayIsCaughtUp() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        let firstMorning = Support.date("2030-03-01", 13, 0, calendar: calendar)
        LoveReveal.catchUp(pack: pack, state: &state, now: firstMorning, calendar: calendar)
        XCTAssertEqual(state.revealed.keys.sorted(), ["2030-03-01"])

        // Back a week later, at 07:00 -- before today's minute.
        let back = Support.date("2030-03-08", 7, 0, calendar: calendar)
        LoveReveal.catchUp(pack: pack, state: &state, now: back, calendar: calendar)

        XCTAssertEqual(state.revealed.keys.sorted(), (0..<7).map { LoveDay.adding($0, to: "2030-03-01")! })
        XCTAssertEqual(Set(state.revealed.values.map(\.messageId)).count, 7)
        XCTAssertEqual(state.messageBox.first?.day, "2030-03-07")
    }

    func testCatchUpIsBounded() {
        let pack = Support.pack(dailyCount: 50)
        var state = LoveState(packId: pack.packId, importDay: "2030-01-01")
        let now = Support.date("2030-12-31", 13, 0, calendar: calendar)

        LoveReveal.catchUp(pack: pack, state: &state, now: now, maxDays: 30, calendar: calendar)

        XCTAssertEqual(state.revealed.count, 30)
        XCTAssertEqual(state.revealed.keys.min(), "2030-12-02")
    }

    // MARK: Hearts and coupons

    func testHeartsAreEarnedOnceAndCouponsCostThem() {
        var state = LoveState(packId: "p", importDay: "2030-03-01")
        let coupon = LovePackCoupon(id: "c001", title: "Večeře", price: 40)
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        XCTAssertTrue(state.earnHearts(achievementId: "p.genin", amount: 30, at: now))
        XCTAssertFalse(state.earnHearts(achievementId: "p.genin", amount: 30, at: now))
        XCTAssertEqual(state.heartBalance, 30)
        XCTAssertEqual(state.redeem(coupon, at: now), .notEnough(missing: 10))

        state.earnHearts(achievementId: "p.chunin", amount: 25, at: now)
        XCTAssertEqual(state.redeem(coupon, at: now), .redeemed(balance: 15))
        XCTAssertEqual(state.redeem(coupon, at: now), .alreadyRedeemed)
        XCTAssertEqual(state.redeemedCoupons.map { $0.couponId }, ["c001"])
    }

    func testFavourites() {
        var state = LoveState(packId: "p", importDay: "2030-03-01")
        state.setFavorite("d002", true)
        state.setFavorite("d001", true)
        state.setFavorite("d002", true)
        XCTAssertEqual(state.favorites, ["d001", "d002"])
        state.setFavorite("d001", false)
        XCTAssertEqual(state.favorites, ["d002"])
    }
}
