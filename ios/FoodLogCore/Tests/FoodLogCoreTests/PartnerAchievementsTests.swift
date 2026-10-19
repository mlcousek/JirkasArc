// PartnerAchievementsTests.swift
//
// add-partner-love-theme D9, spec partner-achievements: the theme-only
// achievements unlock by their rules from the import day on, pay hearts
// once (never XP), and exist only with the pack content they need.

import XCTest
@testable import FoodLogCore

final class PartnerAchievementsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func reveal(_ state: inout LoveState, days: [String]) {
        for (index, day) in days.enumerated() {
            state.revealed[day] = RevealedLoveMessage(day: day, messageId: "d\(index)", text: "x", revealedAt: now, isRepeat: false)
        }
    }

    private func days(from start: String, count: Int) -> [String] {
        (0..<count).map { LoveDay.adding($0, to: start)! }
    }

    func testTheFirstMessagePaysItsHeartsOnce() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        reveal(&state, days: ["2030-03-01"])

        let first = PartnerAchievements.award(pack: pack, facts: .init(), state: &state, now: now)
        let again = PartnerAchievements.award(pack: pack, facts: .init(), state: &state, now: now)

        XCTAssertEqual(first.map(\.id), ["p.firstnote"])
        XCTAssertEqual(again, [])
        XCTAssertEqual(state.heartBalance, 5)
    }

    func testNothingBeforeTheImportDayCounts() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-10")
        reveal(&state, days: days(from: "2030-03-01", count: 7))

        let unlocked = PartnerAchievements.award(pack: pack, facts: .init(), state: &state, now: now)

        XCTAssertFalse(unlocked.contains { $0.id == "p.week" || $0.id == "p.firstnote" })
    }

    func testAWeekInARowAndCounts() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        reveal(&state, days: days(from: "2030-03-01", count: 6) + ["2030-03-08"])
        XCTAssertFalse(PartnerAchievements.holds("p.week", facts: .init(), state: state), "a gap on 03-07")
        reveal(&state, days: days(from: "2030-03-01", count: 7))
        XCTAssertTrue(PartnerAchievements.holds("p.week", facts: .init(), state: state))
    }

    func testStreakRanksAreCappedAtTheDaysSinceImport() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        // A 40-day streak that began before the import, on the import day:
        // capped to 1 day, so "Jonin" (30) does not unlock in a burst.
        var facts = PartnerAchievementFacts(streak: min(40, 1))
        XCTAssertTrue(PartnerAchievements.award(pack: pack, facts: facts, state: &state, now: now).isEmpty)
        facts.streak = 30
        let unlocked = PartnerAchievements.award(pack: pack, facts: facts, state: &state, now: now).map(\.id)
        XCTAssertEqual(unlocked, ["p.genin", "p.jonin"])
        XCTAssertEqual(state.heartBalance, 45)
    }

    func testFoodWaterAndRamenRules() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        let facts = PartnerAchievementFacts(allMainMealsDays: 7, waterGoalDays: 7, loggedRamen: true, sameFoodDays: 5)
        let unlocked = Set(PartnerAchievements.award(pack: pack, facts: facts, state: &state, now: now).map(\.id))
        XCTAssertEqual(unlocked, ["p.chunin", "p.water", "p.ramen", "p.clone"])
    }

    func testSecretsAndMarks() {
        let pack = LoveTestSupport.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-01")
        state.mark(PartnerAchievements.Mark.heartTaps, at: now)
        state.mark(PartnerAchievements.Mark.nightBox, at: now)
        for day in days(from: "2030-03-01", count: 5) { state.mark(PartnerAchievements.Mark.quickOpen(day), at: now) }
        let unlocked = Set(PartnerAchievements.award(pack: pack, facts: .init(), state: &state, now: now).map(\.id))
        XCTAssertEqual(unlocked, ["p.heart10", "p.night", "p.morning"])
        XCTAssertTrue(PartnerAchievements.all.first { $0.id == "p.heart10" }!.isSecret)
    }

    func testScrollAndCouponAchievementsNeedThatContent() {
        let bare = LoveTestSupport.pack()
        XCTAssertFalse(PartnerAchievements.available(for: bare).contains { $0.id == "p.scroll" || $0.id == "p.coupon" })

        let full = LovePack(
            packId: "p", nickname: "Ninja", signature: "", startDate: "2030-01-01", seed: "s",
            daily: [LovePackDaily(id: "d001", text: "x")],
            openWhen: [LovePackOpenWhen(id: "o1", title: "t", text: "x")],
            coupons: [LovePackCoupon(id: "c001", title: "t", price: 5)]
        )
        var state = LoveState(packId: "p", importDay: "2030-03-01")
        state.openedScrolls["o1"] = now
        state.earnHearts(achievementId: "test", amount: 5, at: now)
        _ = state.redeem(full.coupons[0], at: now)
        let unlocked = Set(PartnerAchievements.award(pack: full, facts: .init(), state: &state, now: now).map(\.id))
        XCTAssertTrue(unlocked.isSuperset(of: ["p.scroll", "p.coupon"]))
    }

    func testEveryAchievementHasCzechWordsInTheTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GarminFood/PartnerTheme/Resources/partner-theme.cs.json")
        let table = try PartnerThemeContent.decode(Data(contentsOf: url))
        XCTAssertEqual(Set(PartnerAchievements.all.map(\.id)), Set(table.achievements.keys))
    }
}
