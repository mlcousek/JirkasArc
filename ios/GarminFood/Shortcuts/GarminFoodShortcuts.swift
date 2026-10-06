// GarminFoodShortcuts.swift
//
// Siri/Spotlight entry points (add-glanceable-surfaces design.md D5,
// tasks.md 20.1; add-interactive-habits D10; add-training-shortcuts-and-
// widgets design D8): SEVEN shortcuts. Apple's compile-time cap is ten --
// an eleventh is a build error, not a warning -- so count before adding
// one (three are left). Every phrase includes `\(.applicationName)` per
// Apple's own requirement -- omitting it is a compile-time diagnostic on
// `AppShortcutsProvider`, not just a style guideline.
//
// `OpenBarcodeScannerIntent` and `MorningCheckInIntent` are reused as-is
// from `Shared/` (the same types the Controls use) -- one intent, several
// entry points, matching openspec/config.yaml's "small, composable" spirit.
// `LogWeightIntent` and `LogWaterIntent` are app-only
// (LogWeightAndWaterIntents.swift), like the two food intents.
//
// A phrase may carry ONE parameter, and it must be an AppEnum or AppEntity:
// the check-in's light is one ("Green in ..."); a weight in kilograms or an
// amount in millilitres is not, so those two shortcuts have fixed phrases
// and ask for (weight) or default (one glass) the number.
//
// Localization (add-localization Wave 5): the phrases' Czech variants live
// in `Resources/AppShortcuts.xcstrings`, keyed by the English phrase with
// `\(.applicationName)` written as `${applicationName}` and a parameter as
// `${light}` -- a phrase changed here needs its key changed there too.
// `shortTitle`s and the intents' titles/descriptions/dialogs are ordinary
// `Localizable.xcstrings` keys.

import AppIntents

struct GarminFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTopQuickPickIntent(),
            phrases: [
                "Log my usual food in \(.applicationName)",
                "Log the usual in \(.applicationName)"
            ],
            shortTitle: "Log Usual",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogNamedFoodIntent(),
            phrases: [
                "Log a food in \(.applicationName)",
                "Log a food by name in \(.applicationName)"
            ],
            shortTitle: "Log a Food",
            systemImageName: "text.magnifyingglass"
        )
        AppShortcut(
            intent: OpenBarcodeScannerIntent(),
            phrases: [
                "Scan a barcode in \(.applicationName)",
                "Open \(.applicationName) to scan a barcode"
            ],
            shortTitle: "Scan Barcode",
            systemImageName: "barcode.viewfinder"
        )
        // add-training-shortcuts-and-widgets D1: "Amber in Jirka's Arc"
        // records that light; "Morning check-in in Jirka's Arc" asks which
        // (the intent's light has no default). Opens the app to record, like
        // the Controls (Shared/MorningCheckInIntents.swift's header).
        AppShortcut(
            intent: MorningCheckInIntent(),
            phrases: [
                "Morning check-in in \(.applicationName)",
                "\(\.$light) in \(.applicationName)",
                "Check in \(\.$light) in \(.applicationName)"
            ],
            shortTitle: "Morning Check-in",
            systemImageName: "sunrise"
        )
        // D5: Siri asks for the kilograms; water is one glass unless a
        // shortcut sets the amount.
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log weight in \(.applicationName)",
                "Log my weight in \(.applicationName)"
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop"
        )
        // add-interactive-habits D10: Siri asks which habit (the ladder's
        // active ones, from the cached plan). Records nothing without a
        // working vault connection.
        AppShortcut(
            intent: TickHabitIntent(),
            phrases: [
                "Tick a habit in \(.applicationName)",
                "Mark a habit done in \(.applicationName)"
            ],
            shortTitle: "Tick Habit",
            systemImageName: "checkmark.circle"
        )
    }
}
