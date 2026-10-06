// GoalStatusEvaluatorTests.swift
//
// add-standalone-mode 2.4 (design D11): the goal-met judgement moved out of
// the app's `GamificationEngine.refreshGoalStatus` must give the SAME
// answer for every Garmin log it used to judge. `legacyJudgement` below is
// a verbatim copy of the engine's former inline code; every fixture (logs
// decoded from Garmin-shaped JSON, as MealDashboardTests does) is judged
// by both and compared, plus the rules spelled out one by one. A local day
// built by `LocalNutritionReader` is judged by the same function.

import XCTest
@testable import FoodLogCore
import GarminKit

final class GoalStatusEvaluatorTests: XCTestCase {
    private func log(_ json: String) throws -> DailyFoodLog {
        try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    /// The engine's code before this change, kept verbatim as the oracle.
    private func legacyJudgement(_ log: DailyFoodLog) -> DayGoalJudgement? {
        func metAtLeast(actual: Double?, goal: Double?) -> Bool {
            guard let actual, let goal, goal > 0 else { return false }
            return actual >= goal
        }
        guard let goals = log.dailyNutritionGoals,
              let content = log.dailyNutritionContent
        else { return nil }
        return DayGoalJudgement(
            metCalorieGoal: CalorieBand.isGoalMet(consumed: content.calories, goal: goals.calories ?? goals.adjustedCalories),
            metProteinGoal: metAtLeast(actual: content.protein, goal: goals.protein ?? goals.adjustedProtein),
            metCarbGoal: metAtLeast(actual: content.carbs, goal: goals.carbs ?? goals.adjustedCarbs),
            metFatGoal: metAtLeast(actual: content.fat, goal: goals.fat ?? goals.adjustedFat)
        )
    }

    private let garminFixtures: [String] = [
        // On target, every macro met.
        #"{ "dailyNutritionGoals": { "calories": 2000, "protein": 120, "carbs": 200, "fat": 60 }, "dailyNutritionContent": { "calories": 2010, "protein": 130, "carbs": 210, "fat": 61 } }"#,
        // Under target, macros short.
        #"{ "dailyNutritionGoals": { "calories": 2000, "protein": 120, "carbs": 200, "fat": 60 }, "dailyNutritionContent": { "calories": 1500, "protein": 80, "carbs": 150, "fat": 40 } }"#,
        // Over target.
        #"{ "dailyNutritionGoals": { "calories": 2000 }, "dailyNutritionContent": { "calories": 2400, "protein": 50 } }"#,
        // A run: adjusted is higher, but the fixed goal is judged.
        #"{ "dailyNutritionGoals": { "calories": 2300, "adjustedCalories": 2900, "protein": 115, "adjustedProtein": 140 }, "dailyNutritionContent": { "calories": 2310, "protein": 120 } }"#,
        // Only adjusted values: they are the fallback.
        #"{ "dailyNutritionGoals": { "adjustedCalories": 1800, "adjustedProtein": 100 }, "dailyNutritionContent": { "calories": 1790, "protein": 100 } }"#,
        // A zero macro goal is no goal.
        #"{ "dailyNutritionGoals": { "calories": 2000, "fat": 0 }, "dailyNutritionContent": { "calories": 0, "fat": 10 } }"#,
        // Empty content object.
        #"{ "dailyNutritionGoals": { "calories": 2000 }, "dailyNutritionContent": {} }"#,
        // No goals.
        #"{ "dailyNutritionContent": { "calories": 2000 } }"#,
        // No content.
        #"{ "dailyNutritionGoals": { "calories": 2000 } }"#,
        // Nothing at all.
        #"{ }"#,
    ]

    // MARK: - Entries being deleted (improve-food-day-flow, review 2026-10-06)

    /// A day at 2000 of 2000 kcal with 130 g protein of 120 -- on the
    /// strength of a 400 kcal / 30 g protein entry ("log-b").
    private func dayWithTwoEntries() throws -> DailyFoodLog {
        try log("""
        { "dailyNutritionGoals": { "calories": 2000, "protein": 120, "carbs": 200, "fat": 60 },
          "dailyNutritionContent": { "calories": 2000, "protein": 130, "carbs": 210, "fat": 62 },
          "mealDetails": [ { "meal": { "mealName": "LUNCH" }, "loggedFoods": [
            { "logId": "log-a", "servingQty": 1,
              "foodMetaData": { "foodId": "f1", "foodName": "Rice" },
              "nutritionContent": { "servingId": "s1", "calories": 1600, "protein": 100, "carbs": 170, "fat": 50 } },
            { "logId": "log-b", "servingQty": 2,
              "foodMetaData": { "foodId": "f2", "foodName": "Bread" },
              "nutritionContent": { "servingId": "s2", "calories": 200, "protein": 15, "carbs": 20, "fat": 6 } }
          ] } ] }
        """)
    }

    func testAnEntryBeingDeletedDoesNotMakeTheDayMet() throws {
        let day = try dayWithTwoEntries()

        let raw = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: nil))
        XCTAssertTrue(raw.metCalorieGoal, "Garmin's own totals still contain the entry")
        XCTAssertTrue(raw.metProteinGoal)

        // 2 x (200 kcal, 15 g protein, 20 g carbs, 6 g fat) come off.
        let judged = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: nil, excludingLogIds: ["log-b"]))
        XCTAssertFalse(judged.metCalorieGoal, "1600 of 2000 kcal is not on target")
        XCTAssertFalse(judged.metProteinGoal, "100 g of 120 g")
        XCTAssertFalse(judged.metCarbGoal, "170 g of 200 g")
        XCTAssertFalse(judged.metFatGoal, "50 g of 60 g")
    }

    func testNothingToLeaveOutIsTheOrdinaryJudgement() throws {
        let day = try dayWithTwoEntries()
        let ordinary = GoalStatusEvaluator.evaluate(day, fuel: nil)

        XCTAssertEqual(GoalStatusEvaluator.evaluate(day, fuel: nil, excludingLogIds: []), ordinary)
        XCTAssertEqual(GoalStatusEvaluator.evaluate(day, fuel: nil, excludingLogIds: ["not-in-this-day"]), ordinary,
                       "a confirmed delete this read already reflects changes nothing")
        // No goals, no content: still no judgement.
        XCTAssertNil(GoalStatusEvaluator.evaluate(try log("{ }"), fuel: nil, excludingLogIds: ["log-b"]))
    }

    func testTheCarbBandIsJudgedWithoutTheEntryBeingDeletedToo() throws {
        let day = try dayWithTwoEntries()
        // The plan asks for 190-260 g of carbs: 210 g with the entry, 170 g without.
        let band = FuelDayTarget(carbsMinG: 190, carbsMaxG: 260, proteinG: 100, hasTrainingSessions: true)

        let raw = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: band))
        XCTAssertTrue(raw.metCarbGoal)

        let judged = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: band, excludingLogIds: ["log-b"]))
        XCTAssertFalse(judged.metCarbGoal, "170 g is under the band")
        XCTAssertFalse(judged.metCalorieGoal, "with a band, calories follow the carbs")
        XCTAssertTrue(judged.metProteinGoal, "100 g is about the plan's 100 g")
    }

    func testATotalNeverGoesBelowZero() {
        XCTAssertEqual(GoalStatusEvaluator.remaining(100, minus: 250), 0)
        XCTAssertEqual(GoalStatusEvaluator.remaining(100, minus: 40), 60)
        XCTAssertNil(GoalStatusEvaluator.remaining(nil, minus: 40), "an unknown total stays unknown")
    }

    func testEveryGarminFixtureIsJudgedExactlyAsBefore() throws {
        for json in garminFixtures {
            let decoded = try log(json)
            XCTAssertEqual(GoalStatusEvaluator.evaluate(decoded), legacyJudgement(decoded), json)
        }
    }

    func testTheFixedGoalIsJudgedNotTheAdjustedOne() throws {
        let judged = GoalStatusEvaluator.evaluate(try log(garminFixtures[3]))

        XCTAssertEqual(judged?.metCalorieGoal, true, "2310 of the fixed 2300, not of the post-run 2900")
        XCTAssertEqual(judged?.metProteinGoal, true, "120 of 115, not of 140")
    }

    func testMacrosAreMinimumsAndCaloriesABand() throws {
        let under = GoalStatusEvaluator.evaluate(try log(garminFixtures[1]))
        let over = GoalStatusEvaluator.evaluate(try log(garminFixtures[2]))

        XCTAssertEqual(under, DayGoalJudgement(metCalorieGoal: false, metProteinGoal: false, metCarbGoal: false, metFatGoal: false))
        XCTAssertEqual(over?.metCalorieGoal, false, "over the band is not 'met'")
        XCTAssertEqual(over?.metProteinGoal, false, "no protein goal: not met")
    }

    func testNoGoalsOrNoContentRecordsNothing() throws {
        XCTAssertNil(GoalStatusEvaluator.evaluate(try log(garminFixtures[7])))
        XCTAssertNil(GoalStatusEvaluator.evaluate(try log(garminFixtures[8])))
        XCTAssertNil(GoalStatusEvaluator.evaluate(try log(garminFixtures[9])))
    }

    func testAZeroGoalIsNoGoal() {
        XCTAssertFalse(GoalStatusEvaluator.metAtLeast(actual: 10, goal: 0))
        XCTAssertFalse(GoalStatusEvaluator.metAtLeast(actual: nil, goal: 50))
        XCTAssertTrue(GoalStatusEvaluator.metAtLeast(actual: 50, goal: 50))
    }

    // MARK: A local day, same judgement

    private func entry(_ kcal: Double, protein: Double, meal: MealType) -> LocalLogEntry {
        LocalLogEntry(
            day: "2026-09-25",
            mealType: meal,
            loggedAt: Date(timeIntervalSince1970: 1_790_000_000),
            food: LocalFoodRef(id: "f-\(kcal)", source: .custom, name: "Food"),
            serving: Serving(id: "s", unit: "g", numberOfUnits: 100, calories: kcal, carbs: 0, protein: protein, fat: 0),
            quantity: 1
        )
    }

    func testALocalDayIsJudgedByTheSameRules() {
        let entries = [entry(900, protein: 60, meal: .breakfast), entry(1100, protein: 70, meal: .dinner)]
        let withGoals = LocalNutritionReader.dayLog(
            date: "2026-09-25", entries: entries,
            goals: NutritionGoals(calories: 2000, carbs: 250, fat: 70, protein: 120)
        )

        let judged = GoalStatusEvaluator.evaluate(withGoals)

        XCTAssertEqual(judged, DayGoalJudgement(metCalorieGoal: true, metProteinGoal: true, metCarbGoal: false, metFatGoal: false))
        XCTAssertEqual(judged, legacyJudgement(withGoals))
    }

    func testALocalDayWithoutAGoalRecordsNothing() {
        let noGoals = LocalNutritionReader.dayLog(date: "2026-09-25", entries: [entry(2000, protein: 100, meal: .lunch)], goals: nil)

        XCTAssertNil(GoalStatusEvaluator.evaluate(noGoals), "wave 4 supplies local goals; until then no goal status, like Garmin with no goals")
    }
}
