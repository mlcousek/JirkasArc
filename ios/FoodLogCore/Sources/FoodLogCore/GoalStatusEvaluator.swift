// GoalStatusEvaluator.swift
//
// The "did this day meet its goals?" judgement (add-standalone-mode D11,
// task 2.4), moved unchanged out of the app's
// `GamificationEngine.refreshGoalStatus` so it is pure, unit-tested, and
// the same code for a Garmin day and a local one (`LocalNutritionReader`
// builds the same `DailyFoodLog` shape). The engine still owns fetching
// the log and recording the result; only the judgement lives here.
//
// The rules, exactly as they were:
//   - no goals or no content on the day: no judgement (nothing recorded);
//   - the FIXED goal is used, `adjusted*` only as a fallback for a payload
//     with no base value (today-dashboard spec, owner decision 2026-09-23:
//     burned calories must not move "goal met");
//   - calories: met when the day lands in `CalorieBand.onTarget`;
//   - protein/carbs/fat: met when at least the goal, and a goal of 0 or
//     less is no goal.
//
// Returns its own small value, not Gamification's `DailyGoalStatus`:
// FoodLogCore doesn't depend on Gamification (the dependency runs the
// other way), and Gamification doesn't import GarminKit, so the app maps
// one to the other. Tests: GoalStatusEvaluatorTests.
//
// add-winter-arc-nutrition-and-rewards (A1): `evaluate(_:fuel:)` is the
// training experience's judgement -- with a plan day's `FuelDayTarget` the
// day is judged by the carb band (and the plan's protein) instead of the
// fixed calorie target, so eating inside the band is never a missed goal
// (`FuelDayEvaluator.judge`). Without a target it is exactly `evaluate(_:)`.

import Foundation
import GarminKit

public struct DayGoalJudgement: Sendable, Equatable {
    public let metCalorieGoal: Bool
    public let metProteinGoal: Bool
    public let metCarbGoal: Bool
    public let metFatGoal: Bool

    public init(metCalorieGoal: Bool, metProteinGoal: Bool, metCarbGoal: Bool, metFatGoal: Bool) {
        self.metCalorieGoal = metCalorieGoal
        self.metProteinGoal = metProteinGoal
        self.metCarbGoal = metCarbGoal
        self.metFatGoal = metFatGoal
    }
}

public enum GoalStatusEvaluator {
    /// The day's judgement, or `nil` when the log carries no goals or no
    /// content -- then nothing is recorded, as before.
    public static func evaluate(_ log: DailyFoodLog) -> DayGoalJudgement? {
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

    /// The training experience's judgement (see the header). With a
    /// target, a day with content but no Garmin goals is still judged when
    /// the target has a carb band (the band IS the goal); otherwise the
    /// same `nil` rule as `evaluate(_:)`.
    public static func evaluate(_ log: DailyFoodLog, fuel: FuelDayTarget?) -> DayGoalJudgement? {
        guard let fuel else { return evaluate(log) }
        guard let content = log.dailyNutritionContent else { return nil }
        let goals = log.dailyNutritionGoals
        guard goals != nil || fuel.carbBand != nil else { return nil }
        return FuelDayEvaluator.judge(
            calories: content.calories,
            protein: content.protein,
            carbs: content.carbs,
            fat: content.fat,
            calorieGoal: goals.flatMap { $0.calories ?? $0.adjustedCalories },
            proteinGoal: goals.flatMap { $0.protein ?? $0.adjustedProtein },
            carbGoal: goals.flatMap { $0.carbs ?? $0.adjustedCarbs },
            fatGoal: goals.flatMap { $0.fat ?? $0.adjustedFat },
            target: fuel
        )
    }

    /// The judgement with some entries of the day LEFT OUT of what was
    /// eaten (improve-food-day-flow, review 2026-10-06): `excludingLogIds`
    /// are entries the owner deleted that Garmin's day still lists -- a
    /// delete waiting to be sent, or one Garmin confirmed that this read
    /// does not reflect yet (`MealDashboard.removedLogIds`). Garmin's own
    /// totals still contain them, so judging those totals would record a
    /// day as "goal met" on the strength of an entry that is being deleted.
    /// Their calories and macronutrients (per serving x quantity, as the
    /// dashboard counts them) come off first; a total never goes below 0.
    ///
    /// With nothing to leave out -- no ids, or none of them listed in this
    /// log -- it is exactly `evaluate(_:fuel:)`.
    public static func evaluate(_ log: DailyFoodLog, fuel: FuelDayTarget?, excludingLogIds: Set<String>) -> DayGoalJudgement? {
        let removed = MealDashboard.syncedEntries(MealDashboard.loggedFoods(in: log, withLogIds: excludingLogIds))
        guard !removed.isEmpty, let content = log.dailyNutritionContent else {
            return evaluate(log, fuel: fuel)
        }
        let calories = remaining(content.calories, minus: MealDashboard.sum(removed, \.calories))
        let protein = remaining(content.protein, minus: MealDashboard.sum(removed, \.protein))
        let carbs = remaining(content.carbs, minus: MealDashboard.sum(removed, \.carbs))
        let fat = remaining(content.fat, minus: MealDashboard.sum(removed, \.fat))
        let goals = log.dailyNutritionGoals

        if let fuel {
            guard goals != nil || fuel.carbBand != nil else { return nil }
            return FuelDayEvaluator.judge(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                calorieGoal: goals.flatMap { $0.calories ?? $0.adjustedCalories },
                proteinGoal: goals.flatMap { $0.protein ?? $0.adjustedProtein },
                carbGoal: goals.flatMap { $0.carbs ?? $0.adjustedCarbs },
                fatGoal: goals.flatMap { $0.fat ?? $0.adjustedFat },
                target: fuel
            )
        }
        guard let goals else { return nil }
        return DayGoalJudgement(
            metCalorieGoal: CalorieBand.isGoalMet(consumed: calories, goal: goals.calories ?? goals.adjustedCalories),
            metProteinGoal: metAtLeast(actual: protein, goal: goals.protein ?? goals.adjustedProtein),
            metCarbGoal: metAtLeast(actual: carbs, goal: goals.carbs ?? goals.adjustedCarbs),
            metFatGoal: metAtLeast(actual: fat, goal: goals.fat ?? goals.adjustedFat)
        )
    }

    /// `total` less `part`, never below 0; an unknown total stays unknown.
    static func remaining(_ total: Double?, minus part: Double) -> Double? {
        total.map { max(0, $0 - part) }
    }

    public static func metAtLeast(actual: Double?, goal: Double?) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return actual >= goal
    }
}
