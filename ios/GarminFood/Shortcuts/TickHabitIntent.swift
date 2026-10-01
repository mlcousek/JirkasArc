// TickHabitIntent.swift
//
// "Tick a habit" from Shortcuts and Siri (add-interactive-habits design
// D10): the owner picks one of the ladder's active habits and it is marked
// done for today's training day, without opening the app's screens.
//
// It lives in the app target, like `LogTopQuickPickIntent` (read its header):
// an App Shortcut runs in the app's own process, so it can use TrainingCore
// and the app's one recorder directly. That is also why it is NOT a
// lock-screen Control: the widget extension can't link TrainingCore and
// has no App Group to read the cached plan from, so it could not list the
// habits; a Control per habit would need the three check-in Controls'
// `openAppWhenRun` hook and a fixed habit list the plan doesn't have. No
// new target, no new App ID.
//
// What it does, all from the cached projection (it may run offline):
//   - the habit choices are the ladder's active habits
//     (`HabitQuickTick.choices`); Siri asks which one when the phrase
//     doesn't say;
//   - the tick is `habit.tick {date: today's training day, habitId,
//     done: true}`, recorded through `TrainingEventsService` -- local and
//     durable, delivered later like a tap on Today. A multi-dose habit is
//     marked done for the day (the wire is on/off, decision A42);
//   - a habit the plan doesn't expect today records nothing and says so;
//   - with the vault connection off or never tested it records nothing and
//     throws the check-in Controls' own localized errors.
//
// Depended on by: GarminFoodShortcuts.

import AppIntents
import Foundation
import TrainingCore

/// One of the ladder's active habits, as Shortcuts lists it.
struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitEntityQuery()

    let id: String
    let label: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }
}

struct HabitEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        let all = await Self.activeHabits()
        return all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        await Self.activeHabits()
    }

    /// The cached plan's active habits, in the app's language.
    @MainActor
    static func activeHabits() async -> [HabitEntity] {
        let cached = await VaultServices.shared.projectionStore.loadCached()
        let language = TrainingLanguage.from(preferredLocalizations: Bundle.main.preferredLocalizations)
        return HabitQuickTick.choices(projection: cached?.projection, language: language)
            .map { HabitEntity(id: $0.id, label: $0.label) }
    }
}

struct TickHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick Habit"
    static var description = IntentDescription("Marks one of today's habits as done in Jirka's Arc.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Tick \(\.$habit) in Jirka's Arc")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cached = await VaultServices.shared.projectionStore.loadCached()
        let language = TrainingLanguage.from(preferredLocalizations: Bundle.main.preferredLocalizations)
        let outcome = HabitQuickTick.tick(
            habitID: habit.id,
            projection: cached?.projection,
            language: language,
            now: Date(),
            deviceTimeZone: .current
        )
        switch outcome {
        case .tick(let payload, let label):
            do {
                try await TrainingEventsService.shared.record(.habitTick(payload))
            } catch TrainingEventsService.RecordError.vaultOff {
                throw MorningCheckInControlAction.ActionError.vaultOff
            } catch TrainingEventsService.RecordError.notTested {
                throw MorningCheckInControlAction.ActionError.notTested
            }
            return .result(dialog: "Ticked \(label).")
        case .notPlannedToday(let label):
            return .result(dialog: "\(label) isn't on today's plan. Nothing recorded.")
        case .unknownHabit:
            throw MorningCheckInControlAction.ActionError.notAvailable
        }
    }
}
