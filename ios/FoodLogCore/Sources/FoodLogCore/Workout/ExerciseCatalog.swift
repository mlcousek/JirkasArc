// ExerciseCatalog.swift
//
// add-workout-tracker: the exercises the app can SHOW (what the movement
// looks like, three cues) and recognise by the name the plan writes. The
// plan (the vault's workout library, `Step.name`) stays the owner of WHAT to
// do; this catalog only attaches a picture and cues to a name, so a plan that
// names "Bench press" or "Tlak na lavici" gets its illustration and an
// exercise the catalog does not know still works (a row without pictures).
//
// Adding an exercise is one object in `Resources/exercise-catalog.json` (+ up
// to two images in the app's Resources/Exercises, named by `images`): no code.
// The images come from the public-domain free-exercise-db (Unlicense); a
// curated video link goes in `video`, and without one the screen offers a
// search for the exercise's form.
//
// Pure Foundation, so it is unit-tested here. Depended on by:
// GarminFood/Workout/StrengthWorkoutView.swift, WorkoutLog (the exercise key).

import Foundation

public struct ExerciseText: Codable, Equatable, Sendable {
    public let en: String
    public let cs: String

    public func text(languageCode: String?) -> String {
        languageCode == "cs" ? cs : en
    }
}

public struct ExerciseInfo: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: ExerciseText
    /// Other names the plan may use, any language; matched after folding case
    /// and diacritics.
    public let aliases: [String]
    public let cues: [ExerciseText]
    /// Bundle resource names (jpg) of the movement's frames, in order.
    public let images: [String]
    /// A curated video URL, or nil (the screen then offers a search).
    public let video: String?
}

public struct ExerciseCatalog: Sendable {
    public let exercises: [ExerciseInfo]
    private let keyed: [(key: String, id: String)]

    public init(exercises: [ExerciseInfo]) {
        self.exercises = exercises
        var keys: [(String, String)] = []
        for exercise in exercises {
            for name in [exercise.id, exercise.name.en, exercise.name.cs] + exercise.aliases {
                let key = Self.normalize(name)
                if !key.isEmpty { keys.append((key, exercise.id)) }
            }
        }
        // Longest first, so "romanian deadlift" wins over "deadlift".
        self.keyed = keys.sorted { $0.0.count > $1.0.count }
    }

    /// The catalog in this package's resources; empty (never a crash) when the
    /// file is missing or unreadable.
    public static func bundled() -> ExerciseCatalog {
        guard let url = Bundle.module.url(forResource: "exercise-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exercises = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else {
            return ExerciseCatalog(exercises: [])
        }
        return ExerciseCatalog(exercises: exercises)
    }

    /// The exercise a plan's name stands for: an exact name or alias first,
    /// else the longest alias that appears in the name as whole words
    /// ("Paused barbell bench press" -> bench press); nil when none does.
    public func match(name: String) -> ExerciseInfo? {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return nil }
        let padded = " \(key) "
        let hit = keyed.first { $0.key == key } ?? keyed.first { padded.contains(" \($0.key) ") }
        return hit.flatMap { found in exercises.first { $0.id == found.id } }
    }

    /// The stable key a logged set is filed under: the catalog id, else the
    /// normalised plan name (two spellings of an unknown exercise stay apart).
    public func key(forName name: String) -> String {
        match(name: name)?.id ?? Self.normalize(name)
    }

    /// Lowercase, diacritics folded, anything but letters and digits a single
    /// space: "Tlak na lavici!" == "tlak na lavici".
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .split(separator: " ")
        return words.map { String($0) }.joined(separator: " ")
    }

    /// Where "Watch how" goes without a curated video.
    public static func searchURL(forName name: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) exercise form")]
        return components?.url
    }
}
