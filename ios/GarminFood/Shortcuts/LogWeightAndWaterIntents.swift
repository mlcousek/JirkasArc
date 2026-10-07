// LogWeightAndWaterIntents.swift
//
// The "Log weight" and "Log water" Siri/Spotlight shortcuts
// (add-training-shortcuts-and-widgets design D5). In the app target, not
// `Shared/`, for the reason LogTopQuickPickIntent.swift gives: an App
// Shortcut's intent runs in (or launches) the app's own process by itself,
// so it needs no `openAppWhenRun` and can answer by voice without bringing
// the app forward. The work is `QuickHealthLogAction`
// (Shared/QuickHealthLogIntents.swift), the same action the water Control
// uses: check the number, commit through the weight / hydration
// coordinator (local first, then the outbox), wait briefly for Garmin.
//
// Parameters:
//   - `weightKg` has no default, so Siri asks for it. It can't be part of
//     the phrase: a phrase parameter must be an AppEnum or AppEntity.
//   - `amountML` defaults to one glass. The literal 250 repeats
//     FoodLogCore's `QuickLogInput.defaultGlassML` (a parameter default
//     must be a literal); QuickHealthLogTests pins that number.
// Neither declares an `inclusiveRange:`: the rule that decides is
// `QuickLogInput` (the sheets' bounds), so a number it refuses reaches
// `perform()`, saves nothing and is answered in this app's own words
// ("Nothing saved: the weight must be above 0 and below 500 kg.").
//
// The answer says what actually happened, like LogNamedFoodIntent's: the
// existing "Saved %@ ..." / "Logged %@ to Garmin." sentences with the
// amount ("75.5 kg", "250 ml") where the food's name goes. An expired
// Garmin sign-in is said out loud; the entry is saved either way.
//
// No donation: an App Shortcut is already offered by Spotlight and Siri,
// and a donated weigh-in would have to be removed again when the weigh-in
// is deleted (the siri-and-shortcuts spec's rule for donated logs).

import AppIntents
import Foundation
import FoodLogCore

enum QuickHealthLogDialog {
    /// The spoken answer for `amount` ("75.5 kg", "250 ml").
    static func saved(_ amount: String, delivery: QuickLogDelivery) -> IntentDialog {
        switch delivery {
        case .localOnly:
            return "Saved \(amount)."
        case .queued:
            return "Saved \(amount). It will sync to Garmin in a moment."
        case .delivered:
            return "Logged \(amount) to Garmin."
        case .signedOut:
            return "Saved \(amount), but it can't reach Garmin until you sign in again in Jirka's Arc."
        }
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description = IntentDescription("Saves a weigh-in for now in Jirka's Arc.")

    @Parameter(title: "Weight (kg)", requestValueDialog: "What do you weigh, in kilograms?")
    var weightKg: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$weightKg) kg in Jirka's Arc")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await QuickHealthLogAction.logWeight(kilograms: weightKg)
        let number = NumberDisplay.trimmed(outcome.value, maxFractionDigits: 2)
        let amount = String(localized: "\(number) kg", comment: "A weight in kilograms; %@ is the formatted number.")
        return .result(dialog: QuickHealthLogDialog.saved(amount, delivery: outcome.delivery))
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Saves a drink for now in Jirka's Arc. One 250 ml glass unless you set an amount.")

    @Parameter(title: "Amount (ml)", default: 250)
    var amountML: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amountML) ml of water in Jirka's Arc")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await QuickHealthLogAction.logWater(milliliters: Double(amountML))
        let number = NumberDisplay.whole(outcome.value)
        let amount = String(localized: "\(number) ml", comment: "An amount of water in millilitres; %@ is the formatted number.")
        return .result(dialog: QuickHealthLogDialog.saved(amount, delivery: outcome.delivery))
    }
}
