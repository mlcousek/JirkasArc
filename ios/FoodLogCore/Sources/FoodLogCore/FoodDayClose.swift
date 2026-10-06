// FoodDayClose.swift
//
// improve-food-day-flow (A2, design D6): "That's everything today". Until
// this, a day never ended: nothing said "this is everything I ate", and the
// streak counted a day with one entry the same as a fully logged day, so
// neither the owner nor the training plan could tell a complete log from a
// partial one. Closing a day is that statement.
//
// LOCAL ONLY, like a day note: Garmin has no such thing, so there is no
// outbox and nothing waits on the network. One record per closed day in
// `food-day-closes.json`, keyed by the same `yyyy-MM-dd` string as the day
// on screen (`NutritionDate`). Undo deletes the record.
//
// Rules (`FoodDayCloseRules`):
//   - a day can be closed when it has at least one entry and is not after
//     today;
//   - a closed day STAYS closed when an entry is later added, changed or
//     removed -- it is only marked (`editedAt`) and says "Edited after
//     closing". The app marks it from every change it makes itself
//     (`markEdited`). It is NOT derived by comparing the day's entries with
//     a copy taken at closing: a row's amount is not stable between "queued"
//     and "read back from Garmin", and a day that is not loaded yet has no
//     entries at all, so such a comparison reports edits that never
//     happened. The price: a change made in Garmin Connect is not noticed.
//   - the complete-days streak (`CompleteDaysStreak`) is the run of closed
//     days ending today, or ending yesterday while today is still open; a
//     day that is not closed ends it; an edited day still counts. It sits
//     BESIDE the one-entry streak (Gamification's StreakEngine), which this
//     file never touches.
//
// Rewards for closing a day are deliberately not here (a later change can
// read this store).
//
// Actor-isolated, JSON-file-backed, loaded through the quarantining loader
// -- the same shape as `DayNoteStore`. Depended on by: the app's
// FoodDayCloseController (one instance per process, held by AppServices)
// and, through it, the evening reminder and the `food-log` habit tick.
// Tests: FoodDayCloseTests, StoreFixtureTests.

import Foundation

/// One closed day.
public struct FoodDayClose: Codable, Sendable, Equatable {
    /// `yyyy-MM-dd`.
    public let day: String
    public let closedAt: Date
    /// How many entries the day had when it was closed (for a later reader;
    /// nothing is judged by it).
    public let entryCount: Int
    /// When an entry was first added, changed or removed after closing;
    /// `nil` while the day is as it was closed.
    public var editedAt: Date?

    public init(day: String, closedAt: Date, entryCount: Int, editedAt: Date? = nil) {
        self.day = day
        self.closedAt = closedAt
        self.entryCount = entryCount
        self.editedAt = editedAt
    }

    public var isEditedAfterClosing: Bool { editedAt != nil }
}

/// Why a day could not be closed. Nothing was written.
public enum FoodDayCloseError: Error, Sendable, Equatable {
    /// The day has no entry.
    case nothingLogged
    /// The day is after today.
    case futureDay
    /// Not a `yyyy-MM-dd` day.
    case invalidDay
}

/// The pure rules over one day (tested without a file).
public enum FoodDayCloseRules {
    /// What the close card shows for a day.
    public enum State: Sendable, Equatable {
        /// Nothing to offer: a day after today, or a day without an entry
        /// that is not closed.
        case notOffered
        /// Can be closed now.
        case open
        case closed(editedAfterClosing: Bool)
    }

    public static func isValidDay(_ day: String) -> Bool {
        NutritionDate.noon(ofDayString: day) != nil
    }

    /// `nil` when `day` can be closed; otherwise why not.
    public static func refusal(day: String, today: String, entryCount: Int) -> FoodDayCloseError? {
        guard isValidDay(day) else { return .invalidDay }
        // `yyyy-MM-dd` strings sort chronologically.
        guard day <= today else { return .futureDay }
        guard entryCount >= 1 else { return .nothingLogged }
        return nil
    }

    public static func canClose(day: String, today: String, entryCount: Int) -> Bool {
        refusal(day: day, today: today, entryCount: entryCount) == nil
    }

    /// The card's state for `day`. `record` is the store's record for that
    /// day (a record of another day is ignored).
    public static func state(day: String, today: String, entryCount: Int, record: FoodDayClose?) -> State {
        if let record, record.day == day {
            return .closed(editedAfterClosing: record.isEditedAfterClosing)
        }
        return canClose(day: day, today: today, entryCount: entryCount) ? .open : .notOffered
    }
}

/// Closed days in a row.
public enum CompleteDaysStreak {
    /// The run of closed days ending `today` -- or ending the day before
    /// while `today` is not closed yet (the day isn't over). A day that is
    /// not closed ends the run.
    public static func length(closedDays: Set<String>, today: String, calendar: Calendar = .current) -> Int {
        var cursor: String? = closedDays.contains(today) ? today : previousDay(today, calendar: calendar)
        var count = 0
        // Never more steps than there are closed days.
        while let day = cursor, closedDays.contains(day), count < closedDays.count {
            count += 1
            cursor = previousDay(day, calendar: calendar)
        }
        return count
    }

    /// The day key before `day` (`nil` for a malformed key).
    static func previousDay(_ day: String, calendar: Calendar) -> String? {
        guard let noon = NutritionDate.noon(ofDayString: day, calendar: calendar),
              let moved = NutritionDate.keyCalendar(matching: calendar).date(byAdding: .day, value: -1, to: noon)
        else { return nil }
        return NutritionDate.string(from: moved, calendar: calendar)
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `DayNoteStore`.
public actor FoodDayCloseStore {
    private let fileURL: URL
    private var closesByDay: [String: FoodDayClose] = [:]
    private var loaded = false

    public init(fileURL: URL = FoodDayCloseStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("food-day-closes.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([FoodDayClose].self, from: fileURL, decoder: decoder, category: "FoodDayCloseStore")
        // Unreadable (e.g. before first unlock): retry on the next access.
        loaded = !result.isUnreadable
        let decoded = result.value ?? []
        closesByDay = Dictionary(decoded.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Every save funnels through here; the in-memory copy changes only
    /// once the write has succeeded.
    private func persist(_ updated: [String: FoodDayClose]) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "FoodDayCloseStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(updated.values.sorted { $0.day < $1.day })
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        closesByDay = updated
    }

    /// Every closed day, oldest first.
    public func all() -> [FoodDayClose] {
        loadIfNeeded()
        return closesByDay.values.sorted { $0.day < $1.day }
    }

    public func closedDays() -> Set<String> {
        loadIfNeeded()
        return Set(closesByDay.keys)
    }

    public func record(for day: String) -> FoodDayClose? {
        loadIfNeeded()
        return closesByDay[day]
    }

    /// Closes `day`. A day that is already closed is returned as it is (its
    /// "edited" mark is kept: only undo, then closing again, clears it).
    /// Throws `FoodDayCloseError`, writing nothing, for a day without an
    /// entry, a day after `today` or a malformed day.
    @discardableResult
    public func close(day: String, today: String, entryCount: Int, now: Date = Date()) throws -> FoodDayClose {
        loadIfNeeded()
        if let existing = closesByDay[day] { return existing }
        if let refusal = FoodDayCloseRules.refusal(day: day, today: today, entryCount: entryCount) {
            throw refusal
        }
        let record = FoodDayClose(day: day, closedAt: now, entryCount: entryCount)
        var updated = closesByDay
        updated[day] = record
        try persist(updated)
        return record
    }

    /// Undo: `day` is no longer closed. `false` when it was not closed.
    @discardableResult
    public func reopen(day: String) throws -> Bool {
        loadIfNeeded()
        guard closesByDay[day] != nil else { return false }
        var updated = closesByDay
        updated.removeValue(forKey: day)
        try persist(updated)
        return true
    }

    /// An entry of `day` was added, changed or removed. Marks a CLOSED day
    /// as edited (once: the first change's time is kept) and returns whether
    /// it did; a day that is not closed records nothing.
    @discardableResult
    public func markEdited(day: String, now: Date = Date()) throws -> Bool {
        loadIfNeeded()
        guard var record = closesByDay[day], record.editedAt == nil else { return false }
        record.editedAt = now
        var updated = closesByDay
        updated[day] = record
        try persist(updated)
        return true
    }
}
