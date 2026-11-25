// StrengthWorkoutModel.swift
//
// add-workout-tracker: the exercises of a gym session as the plan wrote them,
// for the screen where the owner ticks sets and logs weights during the
// workout. They are read, never computed: the vault's workout library has the
// `exercise` steps (`Step.name`, `sets`, `reps`, `load`, `tempo`, `side`,
// `note`), so a plan written by the AI with new exercises needs no app change.
//
// Plain data, no catalog and no pictures: matching a name to an illustration
// is FoodLogCore's ExerciseCatalog, joined in the app target, because
// TrainingCore does not depend on FoodLogCore. Texts stay as the plan wrote
// them (names, "8-12", "40 kg"); the screen's own words are localized there.
//
// Depends on PlanBuilder / TrainingSnapshot. Depended on by:
// GarminFood/Workout/StrengthWorkoutView.swift.

import Foundation

public struct PlannedExercise: Equatable, Sendable, Identifiable {
    /// "<position>-<name>": stable for one plan, unique within the workout
    /// even when the plan repeats an exercise.
    public let id: String
    public let name: String
    /// At least 1: a step without `sets` is one set.
    public let setCount: Int
    /// "8-12", "8", nil when the plan gives none.
    public let repsText: String?
    /// "40 kg", nil when the plan gives none.
    public let loadText: String?
    public let tempo: String?
    /// The plan says "each side" (`side: each`).
    public let eachSide: Bool
    public let note: String?
}

public struct StrengthWorkoutModel: Equatable, Sendable {
    public let sessionID: String
    public let title: String
    public let exercises: [PlannedExercise]
}

public extension PlanBuilder {
    /// The exercises of session `id`'s workout (the tapped option's, else the
    /// done option's, else G's, else the first that has any); `nil` when the
    /// session is not in the plan or its workout has no exercise steps.
    func strengthWorkout(sessionId id: String, option: String? = nil) -> StrengthWorkoutModel? {
        guard let snapshot = source.snapshot, let plan = snapshot.plan else { return nil }
        for week in plan.weeks {
            for day in week.days {
                guard let session = day.sessions.first(where: { $0.id == id }) else { continue }
                let exercises = Self.exercises(of: session, option: option, in: snapshot)
                guard !exercises.isEmpty else { return nil }
                return StrengthWorkoutModel(
                    sessionID: session.id,
                    title: format.title(of: session, in: snapshot),
                    exercises: exercises
                )
            }
        }
        return nil
    }

    private static func exercises(of session: Session, option: String?, in snapshot: TrainingSnapshot) -> [PlannedExercise] {
        var workoutIDs: [String?] = []
        if session.options.isEmpty {
            workoutIDs = [session.workout]
        } else {
            let doneCode = session.done?.option?.rawValue
            let preferred = [option, doneCode, OptionCode.g.rawValue].compactMap { $0 }
            let ordered = preferred.compactMap { code in session.options.first { $0.code.rawValue == code } }
                + session.options
            workoutIDs = ordered.map(\.workout)
        }
        for workoutID in workoutIDs {
            guard let workout = snapshot.workout(workoutID) else { continue }
            let planned = plannedExercises(workout.steps)
            if !planned.isEmpty { return planned }
        }
        return []
    }

    private static func plannedExercises(_ steps: [Step]) -> [PlannedExercise] {
        var result: [PlannedExercise] = []
        for step in steps where step.kind?.known == .exercise {
            guard let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            result.append(PlannedExercise(
                id: "\(result.count)-\(name)",
                name: name,
                setCount: max(step.sets ?? 1, 1),
                repsText: step.reps?.text,
                loadText: step.load?.text,
                tempo: step.tempo,
                eachSide: step.side?.known == .each,
                note: step.note
            ))
        }
        return result
    }
}
