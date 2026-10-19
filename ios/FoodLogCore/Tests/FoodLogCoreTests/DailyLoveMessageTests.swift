// DailyLoveMessageTests.swift
//
// add-partner-love-theme D6, spec love-messages "Each day has exactly one
// love message, different every day": one message per day, no repeat
// while unrevealed ones remain, an assignment that never changes, and the
// favourites-first refill once the pack runs out.

import XCTest
@testable import FoodLogCore

final class DailyLoveMessageTests: XCTestCase {
    private func days(from start: String, count: Int) -> [String] {
        (0..<count).map { LoveDay.adding($0, to: start)! }
    }

    func testThirtyDaysGetThirtyDifferentMessages() {
        let pack = LoveTestSupport.pack(dailyCount: 30)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")

        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 30), pack: pack, state: &state)

        XCTAssertEqual(state.assignments.count, 30)
        XCTAssertEqual(Set(state.assignments.values).count, 30)
        XCTAssertFalse(days(from: "2030-03-01", count: 30).contains { DailyLoveMessage.isRepeat(day: $0, state: state) })
    }

    func testTheOrderIsSeededNotThePacksOrder() {
        let pack = LoveTestSupport.pack(dailyCount: 30)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 30), pack: pack, state: &state)

        let inOrder = days(from: "2030-03-01", count: 30).map { state.assignments[$0]! }
        XCTAssertNotEqual(inOrder, pack.daily.map(\.id))
    }

    func testPlanningInAnyOrderGivesTheSameDays() {
        let pack = LoveTestSupport.pack(dailyCount: 30)
        var forward = LoveState(packId: pack.packId, importDay: "2030-03-01")
        var piecewise = forward
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 14), pack: pack, state: &forward)
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 7).reversed(), pack: pack, state: &piecewise)
        DailyLoveMessage.assign(days: days(from: "2030-03-08", count: 7), pack: pack, state: &piecewise)
        XCTAssertEqual(forward.assignments, piecewise.assignments)
    }

    func testAnAssignedDayKeepsItsMessageAfterAReimport() {
        let pack = LoveTestSupport.pack(dailyCount: 10)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 7), pack: pack, state: &state)
        let tomorrow = state.assignments["2030-03-02"]

        let bigger = LoveTestSupport.pack(dailyCount: 30)
        state.reconcile(with: bigger)
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 8), pack: bigger, state: &state)

        XCTAssertEqual(state.assignments["2030-03-02"], tomorrow)
        XCTAssertEqual(DailyLoveMessage.message(for: "2030-03-02", pack: bigger, state: state)?.id, tomorrow)
    }

    func testAPlannedDayWhoseMessageWasRemovedIsRedrawnButARevealedOneIsKept() {
        let pack = LoveTestSupport.pack(dailyCount: 10)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        DailyLoveMessage.assign(days: ["2030-03-01", "2030-03-02"], pack: pack, state: &state)
        let revealedId = state.assignments["2030-03-01"]!
        let plannedId = state.assignments["2030-03-02"]!
        state.revealed["2030-03-01"] = RevealedLoveMessage(day: "2030-03-01", messageId: revealedId, text: "x", revealedAt: Date(), isRepeat: false)

        let smaller = LovePack(
            packId: pack.packId, nickname: pack.nickname, signature: pack.signature, startDate: pack.startDate, seed: pack.seed,
            daily: pack.daily.filter { $0.id != revealedId && $0.id != plannedId }
        )
        state.reconcile(with: smaller)

        XCTAssertEqual(state.assignments["2030-03-01"], revealedId)
        XCTAssertNil(state.assignments["2030-03-02"])
    }

    func testWhenThePoolRunsOutFavouritesComeFirst() {
        let pack = LoveTestSupport.pack(dailyCount: 5)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 5), pack: pack, state: &state)
        for id in ["d002", "d004", "d005"] { state.setFavorite(id, true) }

        DailyLoveMessage.assign(days: days(from: "2030-03-06", count: 3), pack: pack, state: &state)

        let repeats = days(from: "2030-03-06", count: 3).map { state.assignments[$0]! }
        XCTAssertEqual(Set(repeats), ["d002", "d004", "d005"])
        XCTAssertTrue(DailyLoveMessage.isRepeat(day: "2030-03-06", state: state))
    }

    func testWithoutFavouritesTheOneShownLongestAgoComesBack() {
        let pack = LoveTestSupport.pack(dailyCount: 3)
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        DailyLoveMessage.assign(days: days(from: "2030-03-01", count: 3), pack: pack, state: &state)

        DailyLoveMessage.assign(days: ["2030-03-04"], pack: pack, state: &state)

        XCTAssertEqual(state.assignments["2030-03-04"], state.assignments["2030-03-01"])
    }

    func testNothingBeforeTheFirstDay() {
        let pack = LoveTestSupport.pack(dailyCount: 10, startDate: "2030-03-10")
        var state = LoveState(packId: pack.packId, importDay: "2030-03-05")
        DailyLoveMessage.assign(days: days(from: "2030-03-08", count: 4), pack: pack, state: &state)
        XCTAssertEqual(state.assignments.keys.sorted(), ["2030-03-10", "2030-03-11"])

        // Imported after the start date: the import day is the first day.
        var late = LoveState(packId: pack.packId, importDay: "2030-04-01")
        DailyLoveMessage.assign(days: ["2030-03-31", "2030-04-01"], pack: pack, state: &late)
        XCTAssertEqual(late.assignments.keys.sorted(), ["2030-04-01"])
    }
}
