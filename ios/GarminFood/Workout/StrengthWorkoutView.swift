// StrengthWorkoutView.swift
//
// add-workout-tracker: the screen for a gym session while it is happening.
// Per exercise of the plan (TrainingCore.StrengthWorkoutModel, read from the
// vault's workout library -- the phone never writes the plan): what was
// planned (sets x reps, load, tempo), what was lifted last time, one row per
// set for the weight and reps, and "How to do it" -- the movement's two
// frames and three cues from FoodLogCore's ExerciseCatalog, and a way to
// watch it. An exercise the catalog does not know is still listed and
// loggable; it only lacks the pictures.
//
// Every keystroke is saved at once to WorkoutLogStore (local, durable, no
// network wait): leaving the screen or the app mid-workout loses nothing.
// The weights never go to Garmin or the vault.
//
// Pushed from SessionDetailView's "Start workout". Depends on AppEnvironment
// (training, workoutLogStore), FoodLogCore, TrainingCore.

import SwiftUI
import UIKit
import FoodLogCore
import GarminKit
import TrainingCore

struct StrengthWorkoutView: View {
    let sessionID: String
    let option: String?

    @Environment(AppEnvironment.self) private var environment
    @State private var loaded = false
    @State private var logged: [LoggedSet] = []
    @State private var previous: [String: [LoggedSet]] = [:]

    private let catalog = ExerciseCatalog.bundled()

    var body: some View {
        let workout = environment.training.planBuilder().strengthWorkout(sessionId: sessionID, option: option)
        ScrollView {
            if let workout {
                if loaded {
                    VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                        ForEach(workout.exercises) { exercise in
                            let key = catalog.key(forName: exercise.name)
                            ExerciseCard(
                                exercise: exercise,
                                info: catalog.match(name: exercise.name),
                                existing: logged.filter { $0.exerciseKey == key },
                                previous: previous[key] ?? [],
                                onRecord: { number, weight, reps in
                                    record(key: key, number: number, weight: weight, reps: reps)
                                }
                            )
                        }
                    }
                    .padding(Theme.Spacing.md)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.lg)
                }
            } else {
                Text("This session is no longer in the plan")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .card()
                    .padding(Theme.Spacing.md)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background { GradientHeaderBackground() }
        .navigationTitle(workout.map { Text(verbatim: $0.title) } ?? Text("Workout"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let exercises = environment.training.planBuilder().strengthWorkout(sessionId: sessionID, option: option)?.exercises ?? []
        logged = await environment.workoutLogStore.sets(session: sessionID)
        var last: [String: [LoggedSet]] = [:]
        for exercise in exercises {
            let key = catalog.key(forName: exercise.name)
            last[key] = await environment.workoutLogStore.previous(exerciseKey: key, excluding: sessionID)
        }
        previous = last
        loaded = true
    }

    private func record(key: String, number: Int, weight: Double?, reps: Int?) {
        let store = environment.workoutLogStore
        let session = sessionID
        Task {
            do {
                try await store.record(session: session, exerciseKey: key, setNumber: number, weightKg: weight, reps: reps)
            } catch {
                // Loud, not silent: the owner is standing in a gym trusting
                // this is saved. The diagnostics log is where it can be read.
                DiagnosticsLog.log(.error, category: "WorkoutLog", "Saving a set failed: \(error)")
            }
        }
    }
}

// MARK: - One exercise

private struct ExerciseCard: View {
    let exercise: PlannedExercise
    let info: ExerciseInfo?
    let existing: [LoggedSet]
    let previous: [LoggedSet]
    let onRecord: (Int, Double?, Int?) -> Void

    private var languageCode: String? { Bundle.main.preferredLocalizations.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(verbatim: info?.name.text(languageCode: languageCode) ?? exercise.name)
                .font(.headline)
            if let plan = planLine {
                Text(verbatim: plan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let note = exercise.note {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let last = previousLine {
                Label {
                    Text(String(localized: "Last time: \(last)"))
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            ForEach(1...exercise.setCount, id: \.self) { number in
                let saved = existing.first { $0.setNumber == number }
                let before = previous.first { $0.setNumber == number }
                SetRow(
                    number: number,
                    weight: saved?.weightKg,
                    reps: saved?.reps,
                    weightPlaceholder: before?.weightKg.map { SetEntryText.text(weight: $0) } ?? "0",
                    repsPlaceholder: before?.reps.map(String.init) ?? plannedReps ?? "0"
                ) { weight, reps in
                    onRecord(number, weight, reps)
                }
            }
            if let info {
                HowTo(info: info, languageCode: languageCode)
            } else if let url = ExerciseCatalog.searchURL(forName: exercise.name) {
                Link(destination: url) {
                    Label("Watch how", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .card()
    }

    /// "3 × 8-12 · 40 kg · Tempo 3-0-3 · Each side": the plan's own numbers.
    private var planLine: String? {
        var parts: [String] = []
        if let reps = exercise.repsText {
            parts.append("\(exercise.setCount) × \(reps)")
        } else {
            parts.append("\(exercise.setCount) ×")
        }
        if let load = exercise.loadText { parts.append(load) }
        if let tempo = exercise.tempo { parts.append(String(localized: "Tempo \(tempo)")) }
        if exercise.eachSide { parts.append(String(localized: "Each side")) }
        return parts.joined(separator: " · ")
    }

    /// The first number of the plan's reps ("8-12" -> "8"), a placeholder.
    private var plannedReps: String? {
        exercise.repsText?.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
    }

    /// "60 kg × 8, 62.5 kg × 6".
    private var previousLine: String? {
        let parts = previous.compactMap { set -> String? in
            guard set.weightKg != nil || set.reps != nil else { return nil }
            let weight = set.weightKg.map { "\(SetEntryText.text(weight: $0)) kg" } ?? "–"
            return set.reps.map { "\(weight) × \($0)" } ?? weight
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - One set

private struct SetRow: View {
    let number: Int
    let weightPlaceholder: String
    let repsPlaceholder: String
    let onChange: (Double?, Int?) -> Void

    @State private var weightText: String
    @State private var repsText: String

    init(number: Int, weight: Double?, reps: Int?, weightPlaceholder: String, repsPlaceholder: String, onChange: @escaping (Double?, Int?) -> Void) {
        self.number = number
        self.weightPlaceholder = weightPlaceholder
        self.repsPlaceholder = repsPlaceholder
        self.onChange = onChange
        _weightText = State(initialValue: SetEntryText.text(weight: weight))
        _repsText = State(initialValue: reps.map(String.init) ?? "")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Set \(number)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            TextField(weightPlaceholder, text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text("kg").font(.footnote).foregroundStyle(.secondary)
            TextField(repsPlaceholder, text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text("reps").font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: weightText) { _, _ in push() }
        .onChange(of: repsText) { _, _ in push() }
    }

    private func push() {
        onChange(SetEntryText.weight(weightText), SetEntryText.reps(repsText))
    }
}

// MARK: - How to do it

private struct HowTo: View {
    let info: ExerciseInfo
    let languageCode: String?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                let frames = info.images.compactMap(Self.image)
                if !frames.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                            Image(uiImage: frame)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                }
                ForEach(Array(info.cues.enumerated()), id: \.offset) { _, cue in
                    Label {
                        Text(verbatim: cue.text(languageCode: languageCode))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let url = info.video.flatMap(URL.init(string:)) ?? ExerciseCatalog.searchURL(forName: info.name.en) {
                    Link(destination: url) {
                        Label("Watch how", systemImage: "play.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        } label: {
            Label("How to do it", systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Theme.accent)
    }

    /// The frames are plain jpg files in the app bundle's root.
    private static func image(named name: String) -> UIImage? {
        Bundle.main.path(forResource: name, ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }
    }
}
