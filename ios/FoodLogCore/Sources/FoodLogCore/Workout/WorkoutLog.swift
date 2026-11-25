// WorkoutLog.swift
//
// add-workout-tracker: the weights the owner lifted, set by set, filed under
// the session of the plan they belong to. LOCAL ONLY (the vault's contract
// has no place for a set, and the phone never invents one): it is the owner's
// own gym diary, and travels with a backup like the weight and day-note
// stores. One file, `workout-log.json`.
//
// A set is `(exercise key, set number)` inside a session: logging the same
// pair again replaces it (fixing a typo), and clearing both fields removes
// it, so the file never keeps an empty set. `previous` answers "what did I
// lift last time?" from the most recent OTHER session that has the exercise.
//
// Actor-isolated and JSON-file-backed through `FoodLogCoreStorage` like
// `DayNoteStore`. Used by the app's StrengthWorkoutView through the one
// instance `AppServices` holds.

import Foundation

public struct LoggedSet: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: String
    /// `ExerciseCatalog.key(forName:)`.
    public let exerciseKey: String
    /// 1-based position within the exercise.
    public let setNumber: Int
    public var weightKg: Double?
    public var reps: Int?
    public var loggedAt: Date

    public init(id: UUID = UUID(), sessionID: String, exerciseKey: String, setNumber: Int, weightKg: Double?, reps: Int?, loggedAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseKey = exerciseKey
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.loggedAt = loggedAt
    }
}

/// What the weight and reps fields hold, read and written the way the owner
/// types them: a decimal comma is fine ("62,5"), blank is "nothing logged".
public enum SetEntryText {
    public static func weight(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0, value < 1000 else { return nil }
        return value
    }

    public static func reps(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 0, value < 1000 else { return nil }
        return value
    }

    /// 60 -> "60", 62.5 -> "62.5" (no trailing ".0"), for a field's text.
    public static func text(weight: Double?) -> String {
        guard let weight else { return "" }
        return weight.rounded() == weight ? String(Int(weight)) : String(weight)
    }
}

public actor WorkoutLogStore {
    private let fileURL: URL
    private var logged: [LoggedSet] = []
    private var loaded = false

    public init(fileURL: URL = WorkoutLogStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("workout-log.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([LoggedSet].self, from: fileURL, decoder: decoder, category: "WorkoutLogStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        logged = result.value ?? []
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "WorkoutLogStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let ordered = logged.sorted { ($0.sessionID, $0.exerciseKey, $0.setNumber) < ($1.sessionID, $1.exerciseKey, $1.setNumber) }
        try encoder.encode(ordered).write(to: fileURL, options: .atomic)
    }

    /// Every set of a session, in exercise then set order.
    public func sets(session: String) -> [LoggedSet] {
        loadIfNeeded()
        return logged
            .filter { $0.sessionID == session }
            .sorted { ($0.exerciseKey, $0.setNumber) < ($1.exerciseKey, $1.setNumber) }
    }

    /// Writes (or replaces) one set; `nil`/`nil` removes it. Returns the
    /// session's sets afterwards.
    @discardableResult
    public func record(session: String, exerciseKey: String, setNumber: Int, weightKg: Double?, reps: Int?, now: Date = Date()) throws -> [LoggedSet] {
        loadIfNeeded()
        let existing = logged.firstIndex { $0.sessionID == session && $0.exerciseKey == exerciseKey && $0.setNumber == setNumber }
        if weightKg == nil && reps == nil {
            guard let existing else { return self.sets(session: session) }
            logged.remove(at: existing)
        } else if let existing {
            guard logged[existing].weightKg != weightKg || logged[existing].reps != reps else { return self.sets(session: session) }
            logged[existing].weightKg = weightKg
            logged[existing].reps = reps
            logged[existing].loggedAt = now
        } else {
            logged.append(LoggedSet(sessionID: session, exerciseKey: exerciseKey, setNumber: setNumber, weightKg: weightKg, reps: reps, loggedAt: now))
        }
        try persist()
        return self.sets(session: session)
    }

    /// The sets of `exerciseKey` from the most recent session other than
    /// `session`, by when its last set was logged; empty when never lifted.
    public func previous(exerciseKey: String, excluding session: String) -> [LoggedSet] {
        loadIfNeeded()
        let others = logged.filter { $0.exerciseKey == exerciseKey && $0.sessionID != session }
        guard let latest = others.max(by: { $0.loggedAt < $1.loggedAt }) else { return [] }
        return others
            .filter { $0.sessionID == latest.sessionID }
            .sorted { $0.setNumber < $1.setNumber }
    }
}
