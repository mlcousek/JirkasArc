// ActiveCalorieGoal.swift
//
// The day's calorie Target with the day's activity eaten back (owner
// decision 2026-10-19, today-dashboard spec "The home Target adds the
// day's active calories"): the account's base goal (Garmin `calorieGoal`)
// PLUS the active kcal Garmin reports for that day
// (`activeKilocalories` of the daily user summary). Burning 1000 kcal on a
// run raises a 2500 kcal Target to 3500. This reverses the 2026-09-23
// "fixed Target" rule, which left the Target where it was after a long
// run and so asked for far too little food on a training day.
//
// One rule for every place that judges calories against the Target -- the
// Today ring and "kcal left" (`MealDashboard.build`) and "goal met"
// (`GoalStatusEvaluator`) -- so the ring and the reward never disagree.
// Only the day's calories move: macro goals and the per-meal split stay
// Garmin's base values.
//
// Garmin's own `adjusted*` value already contains the burned calories, so
// it is used as it is (never plus the active kcal again) and only when the
// payload has no base value -- the same fallback `MealDashboard.target`
// always had.
//
// Pure, no SwiftUI; tests: ActiveCalorieGoalTests. Depended on by
// MealDashboard, GoalStatusEvaluator.

import Foundation

public enum ActiveCalorieGoal {
    /// The Target for a day: `base` plus `activeKcal` when both are known.
    /// An unknown, zero or negative active figure adds nothing (no read
    /// yet, a rest day, or a bad value); a base goal of 0 or less is no
    /// goal and stays as it is, so "No calorie target" still shows.
    public static func target(adjusted: Double?, base: Double?, activeKcal: Double?) -> Double? {
        guard let base else { return adjusted }
        guard base > 0, let activeKcal, activeKcal.isFinite, activeKcal > 0 else { return base }
        return base + activeKcal
    }
}
