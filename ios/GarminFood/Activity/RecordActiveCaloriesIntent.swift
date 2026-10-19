// RecordActiveCaloriesIntent.swift
//
// add-health-active-calories D3: the Shortcuts action that brings the
// Apple Watch's active calories into a standalone install. The free
// Personal Team has no HealthKit, so the app cannot read Apple Health;
// Shortcuts can. A personal automation runs a shortcut that finds today's
// Active Energy samples, sums them, and hands the number to this action,
// which records it without opening the app (FoodLogCore ActiveCaloriesStore:
// the newest report for a day replaces the older one).
//
// The number arrives as text so whatever Shortcuts passes ("412,5",
// "412.5 kcal") is accepted (ActiveCaloriesIntake); anything else is
// refused with a spoken reason and nothing is saved. A Garmin-connected
// install reads active kcal from Garmin and ignores the report.
//
// App-only (not in Shared/): no Control or widget names it, and an App
// Intent in the app target is offered by the Shortcuts app as it is.

import AppIntents
import Foundation
import FoodLogCore

struct RecordActiveCaloriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Active Calories"
    static var description = IntentDescription("Saves a day's active calories from Apple Health in Jirka's Arc. Meant for a Shortcuts automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Active calories")
    var calories: String

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$calories) active kcal in Jirka's Arc")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.currentDataMode() == .standalone else {
            return .result(dialog: "This phone reads active calories from Garmin, so nothing was saved.")
        }
        guard let kcal = ActiveCaloriesIntake.parseKcal(calories) else {
            return .result(dialog: "That isn't a number of calories. Nothing was saved.")
        }
        let day = NutritionDate.string(from: date ?? Date())
        do {
            try await AppServices.shared.activeCaloriesStore.recordHealth(kcal: kcal, day: day)
        } catch let refusal as ActiveCaloriesRules.Refusal {
            switch refusal {
            case .future, .tooOld:
                return .result(dialog: "Only today and the last 7 days can be recorded. Nothing was saved.")
            case .outOfRange, .notANumber:
                return .result(dialog: "That number of calories can't be right. Nothing was saved.")
            }
        }
        let rounded = Int(kcal.rounded())
        return .result(dialog: "Saved \(rounded) active kcal.")
    }
}
