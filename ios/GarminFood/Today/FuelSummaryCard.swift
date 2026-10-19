// FuelSummaryCard.swift
//
// add-winter-arc-nutrition-and-rewards (A1): what the plan asks to eat on
// a training-experience plan day with a carb band -- carbs against the
// day's g/kg band (x weight) and protein against about 1.6 g/kg. Since
// 2026-10-19 (owner request) it sits UNDER the calorie ring
// (`DaySummaryCard`) instead of replacing it, so it no longer repeats the
// calories or the loading/stale line; the card above shows both. Nothing
// here is ever a warning colour: eating above the band on a training day
// is fine, and a day clearly under the band late in the evening gets one
// gentle, secondary note (FuelDayEvaluator's rule).
//
// improve-food-day-flow (C3): a carb-load day's title names its race
// ("Carb-load day for <race>") when the plan does, and a day with a single
// carbohydrate target says "Below target" or "Target reached" instead of
// the range words.
//
// Every number and judgement comes from FoodLogCore's `FuelDaySummary`;
// this view only lays it out. Without a band (a rest day, no weight known,
// food-first) TodayView shows `DaySummaryCard` alone.
//
// Depends on: FoodLogCore (FuelDaySummary), the design system. Depended on by: TodayView (`.summary` slot).

import SwiftUI
import FoodLogCore

struct FuelSummaryCard: View {
    let summary: FuelDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(titleText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            carbs
            protein

            if summary.showsUnderFuellingNote {
                Label {
                    Text("Carbs are well under today's range. A carb-rich dinner helps you recover for tomorrow.", comment: "Gentle note late in the day when carbs are clearly below the training day's range.")
                } icon: {
                    Image(systemName: "fork.knife")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Title

    private var titleText: String {
        guard summary.isCarbLoad else {
            return String(localized: "Fuel for today's training", comment: "Today summary title in the training experience: carbs and protein for the plan day.")
        }
        if let raceName = summary.raceName {
            return String(localized: "Carb-load day for \(raceName)", comment: "improve-food-day-flow: Today summary title on a carb-load day of the training plan; %@ is the race's name.")
        }
        return String(localized: "Carb-load day", comment: "Today summary title on a carb-load day of the training plan.")
    }

    // MARK: Carbs

    private var carbs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("Carbs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "\(summary.carbsG.wholeNumberText) g"))
                    .font(.macroValue)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOnTarget ? Theme.success : Color.secondary)
            }
            ProgressView(value: summary.carbFraction)
                .tint(Theme.carbs)
            Text(rangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(carbsAccessibilityLabel)
        .accessibilityValue(statusText)
    }

    private var carbsAccessibilityLabel: String {
        if summary.hasSingleTarget {
            return String(localized: "Carbs: \(summary.carbsG.wholeNumberText) grams, target \(summary.carbBand.lowerBound.wholeNumberText) grams", comment: "improve-food-day-flow: VoiceOver for a day with one carbohydrate target: eaten, then the target.")
        }
        return String(localized: "Carbs: \(summary.carbsG.wholeNumberText) grams, range \(summary.carbBand.lowerBound.wholeNumberText) to \(summary.carbBand.upperBound.wholeNumberText) grams", comment: "VoiceOver for the training day's carbs: eaten, then the plan's range.")
    }

    private var rangeText: String {
        let low = summary.carbBand.lowerBound.wholeNumberText
        let high = summary.carbBand.upperBound.wholeNumberText
        if summary.hasSingleTarget || low == high {
            return String(localized: "Target \(low) g", comment: "Carb-load day: the single carbohydrate target in grams.")
        }
        return String(localized: "Range \(low)–\(high) g", comment: "The training day's carbohydrate range in grams (from the plan's g/kg band).")
    }

    /// Inside the range, or at (or above) a single target.
    private var isOnTarget: Bool {
        if let targetStatus = summary.targetStatus {
            return targetStatus == .reached
        }
        return summary.carbStatus == .inBand
    }

    private var statusText: String {
        // improve-food-day-flow (C3): one target is reached or not; more
        // than it is never "above".
        if let targetStatus = summary.targetStatus {
            switch targetStatus {
            case .below: return String(localized: "Below target", comment: "improve-food-day-flow: carbs are under the day's single carbohydrate target (never shown as a warning).")
            case .reached: return String(localized: "Target reached", comment: "improve-food-day-flow: carbs are at or above the day's single carbohydrate target.")
            }
        }
        switch summary.carbStatus {
        case .below: return String(localized: "Below range", comment: "Carbs are under the training day's range (never shown as a warning).")
        case .inBand: return String(localized: "In range", comment: "Carbs are inside the training day's range.")
        case .above: return String(localized: "Above range", comment: "Carbs are over the training day's range (fine on a training day, never a warning).")
        }
    }

    // MARK: Protein

    private var protein: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("Protein")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(String(localized: "\(summary.proteinG.wholeNumberText) g"))
                    .font(.macroValue)
                if let target = summary.proteinTargetG {
                    Text(String(localized: "About \(target.wholeNumberText) g", comment: "The plan's protein target for the day, about 1.6 g per kg."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = summary.proteinFraction {
                ProgressView(value: fraction)
                    .tint(Theme.protein)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
