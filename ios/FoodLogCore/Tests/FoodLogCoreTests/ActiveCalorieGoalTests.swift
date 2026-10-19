// ActiveCalorieGoalTests.swift
//
// The day's calorie Target with the day's activity eaten back
// (ActiveCalorieGoal, owner decision 2026-10-19): base goal + active kcal,
// Garmin's adjusted value only as the no-base fallback and never plus the
// active kcal again.

import XCTest
@testable import FoodLogCore

final class ActiveCalorieGoalTests: XCTestCase {
    func testBurnedCaloriesAreAddedToTheBaseGoal() {
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 2500, activeKcal: 1000), 3500)
    }

    func testUnknownZeroOrNegativeActiveCaloriesAddNothing() {
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 2500, activeKcal: nil), 2500)
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 2500, activeKcal: 0), 2500)
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 2500, activeKcal: -50), 2500)
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 2500, activeKcal: .nan), 2500)
    }

    func testGarminsAdjustedValueIsNotUsedWhenABaseGoalExists() {
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: 3100, base: 2500, activeKcal: 1000), 3500)
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: 3100, base: 2500, activeKcal: nil), 2500)
    }

    func testWithoutABaseGoalTheAdjustedValueIsUsedAsItIs() {
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: 3100, base: nil, activeKcal: 1000), 3100, "adjusted already contains the burned calories")
        XCTAssertNil(ActiveCalorieGoal.target(adjusted: nil, base: nil, activeKcal: 1000))
    }

    func testAZeroBaseGoalStaysNoGoal() {
        XCTAssertEqual(ActiveCalorieGoal.target(adjusted: nil, base: 0, activeKcal: 1000), 0)
    }
}
