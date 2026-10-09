// UsageHistory.swift
//
// The local usage log (design.md D1, tasks 13.1-13.2): one `UsageEvent` per
// successful log, independent of Garmin's own `isFavorite`/`isRecent`
// flags, ranked by a blend of recency and frequency into the "quick pick"
// shelf (food-catalog spec's "A quick-pick shelf is ranked from local
// usage, not from a fresh search" requirement).
//
// STORAGE FORMAT -- documented deliberately plainly here because
// `add-gamification` (a parallel, separate effort) is expected to read this
// same file read-only for streak/XP calculations, per this phase's brief:
//
//   Path:   <Application Support>/FoodLogCore/usage-history.json
//   Shape:  a JSON ARRAY of objects, oldest first, each:
//             { "foodId": "<string>", "servingId": "<string>",
//               "numberOfUnits": <number>, "timestamp": "<ISO 8601 string>",
//               "nutritionDay": "<yyyy-MM-dd>", "mealType": "<MEAL>" }
//   `nutritionDay` (added 2026-09-16) is the date the entry was logged FOR,
//   the same date sent to Garmin, which the user can edit. Files written
//   before it existed lack the key; readers must treat it as optional and
//   fall back to `timestamp`.
//   `mealType` (added 2026-09-23, improve-log-food-shelves) is the meal the
//   entry was logged under, as `GarminKit.MealType`'s raw value
//   ("BREAKFAST" / "LUNCH" / "SNACKS" / "DINNER"). Optional for the same
//   reason: files written before it existed lack the key, and it is omitted
//   (not written as null) when unknown. Events without it simply don't
//   count toward any meal's "Usual for <meal>" shelf (MealUsualRanker).
//   `entryId` and `garminLogId` (added 2026-10-08, harden-gamification-
//   data-integrity 1.1) are the event's identity -- which logged entry it
//   records, so deleting or cancelling THAT entry removes exactly this event
//   and never an identical food logged separately. `entryId` is the
//   app-owned id of the committed entry (the `OutboxEntry.id` in Garmin
//   mode, the `LocalLogEntry.id` in standalone mode, as `uuidString`);
//   `garminLogId` is Garmin's own `logId` for it, linked after
//   Reconciliation confirms the delivery (`linkGarminLogIds`), because a
//   delivered row is deleted by that id once its outbox entry is gone.
//   Both optional and omitted when unknown: events written before they
//   existed have neither, and such an event is never removed by identity.
//   Nothing else is in this file -- no wrapper object, no metadata header.
//   Encoded with `JSONEncoder.dateEncodingStrategy = .iso8601` specifically
//   so a non-Swift reader (or a Swift reader that doesn't want to import
//   this package) can parse it with any standard JSON + ISO 8601 library,
//   not just `Codable` with this exact type. Do not change this shape
//   without updating this comment and coordinating with `add-gamification`.
//   The file is capped at `UsageHistoryStore.maxStoredEvents` entries
//   (oldest trimmed first) so it cannot grow unbounded over the app's
//   lifetime.

import Foundation
import GarminKit

public struct UsageEvent: Codable, Sendable, Equatable {
    public let foodId: String
    public let servingId: String
    public let numberOfUnits: Double
    public let timestamp: Date
    /// `yyyy-MM-dd`: the day this entry was logged for, which is what
    /// streaks and challenges should count, rather than when the button
    /// happened to be pressed. `nil` for events recorded before the field
    /// existed.
    public let nutritionDay: String?
    /// The meal this entry was logged under. `nil` for events recorded
    /// before the field existed (2026-09-23) -- those never count toward a
    /// per-meal ranking, rather than being guessed from the clock.
    public let mealType: MealType?
    /// The committed entry this event records (see the header). `nil` for
    /// events recorded before the field existed (2026-10-08).
    public let entryId: String?
    /// Garmin's `logId` for that entry, once a delivery is confirmed. `nil`
    /// before that, in standalone mode, and for older events.
    public let garminLogId: String?

    public init(
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        timestamp: Date,
        nutritionDay: String? = nil,
        mealType: MealType? = nil,
        entryId: String? = nil,
        garminLogId: String? = nil
    ) {
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.timestamp = timestamp
        self.nutritionDay = nutritionDay
        self.mealType = mealType
        self.entryId = entryId
        self.garminLogId = garminLogId
    }

    /// This event with its identity changed and everything else kept.
    func with(entryId: String?, garminLogId: String?) -> UsageEvent {
        UsageEvent(
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: numberOfUnits,
            timestamp: timestamp,
            nutritionDay: nutritionDay,
            mealType: mealType,
            entryId: entryId,
            garminLogId: garminLogId
        )
    }
}

/// Which logged entry a usage event belongs to: the way a delete names it.
/// A queued (not yet delivered) row and every standalone row are named by
/// the app's own entry id; a row Garmin has confirmed by Garmin's `logId`.
public enum UsageEventIdentity: Sendable, Equatable {
    case entry(String)
    case garminLog(String)

    func matches(_ event: UsageEvent) -> Bool {
        switch self {
        case .entry(let id): return !id.isEmpty && event.entryId == id
        case .garminLog(let id): return !id.isEmpty && event.garminLogId == id
        }
    }
}

/// JSON-file-backed, actor-isolated store -- same pattern as GarminKit's
/// `OutboxStore` (own file, own Application Support subdirectory, atomic
/// writes, `.completeUntilFirstUserAuthentication` protection so a
/// foreground drain right after unlock can still touch it).
public actor UsageHistoryStore {
    public static let maxStoredEvents = 500

    private let fileURL: URL
    private var events: [UsageEvent] = []
    private var loaded = false

    public init(fileURL: URL = UsageHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("usage-history.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([UsageEvent].self, from: fileURL, decoder: decoder, category: "UsageHistoryStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        events = result.value ?? []
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "UsageHistoryStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func all() -> [UsageEvent] {
        loadIfNeeded()
        return events
    }

    /// Appends one event and trims to `maxStoredEvents`, oldest first.
    /// Called once per confirmed log entry (food-log-entry spec's "A
    /// confirmed entry updates local usage ranking" requirement).
    public func record(
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        timestamp: Date = Date(),
        nutritionDay: String? = nil,
        mealType: MealType? = nil,
        entryId: String? = nil
    ) throws {
        loadIfNeeded()
        events.append(UsageEvent(
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: numberOfUnits,
            timestamp: timestamp,
            nutritionDay: nutritionDay,
            mealType: mealType,
            entryId: entryId
        ))
        if events.count > Self.maxStoredEvents {
            events.removeFirst(events.count - Self.maxStoredEvents)
        }
        try persist()
    }

    /// Removes the event of exactly one deleted or cancelled entry
    /// (harden-gamification-data-integrity 1.2). Matches by identity only:
    /// an identical food logged separately, and any event recorded before
    /// identities existed, is left alone. Returns how many were removed
    /// (0 or 1 in practice); writes only when that is more than zero.
    @discardableResult
    public func remove(_ identity: UsageEventIdentity) throws -> Int {
        loadIfNeeded()
        let before = events.count
        events.removeAll { identity.matches($0) }
        let removed = before - events.count
        guard removed > 0 else { return 0 }
        try persist()
        return removed
    }

    /// Records Garmin's `logId` on the events of confirmed deliveries
    /// (`entryId` -> `logId`, see `UsageLogLinks`), so the delivered row
    /// can still be found once its outbox entry is gone. Returns how many
    /// were linked; writes only when that is more than zero.
    @discardableResult
    public func linkGarminLogIds(_ links: [String: String]) throws -> Int {
        loadIfNeeded()
        guard !links.isEmpty else { return 0 }
        var linked = 0
        events = events.map { event in
            guard let entryId = event.entryId, let logId = links[entryId], !logId.isEmpty,
                  event.garminLogId != logId else { return event }
            linked += 1
            return event.with(entryId: entryId, garminLogId: logId)
        }
        guard linked > 0 else { return 0 }
        try persist()
        return linked
    }

    /// Moves an event to the entry that now stands for it: an edit doesn't
    /// record a new event (it isn't another thing eaten), but it replaces
    /// the entry -- a queued entry is swapped for a new one, a delivered one
    /// is superseded by a new outbox entry -- and deleting the edited row
    /// must still remove the original event. The Garmin link is cleared:
    /// the new entry gets its own once delivered. Returns how many moved.
    @discardableResult
    public func reassign(_ identity: UsageEventIdentity, toEntryId newEntryId: String) throws -> Int {
        loadIfNeeded()
        guard !newEntryId.isEmpty else { return 0 }
        var moved = 0
        events = events.map { event in
            guard identity.matches(event) else { return event }
            moved += 1
            return event.with(entryId: newEntryId, garminLogId: nil)
        }
        guard moved > 0 else { return 0 }
        try persist()
        return moved
    }

    /// Fills in the meal of events recorded before `mealType` existed, from
    /// Garmin's own day logs (`UsageMealBackfill`). Runs over the CURRENT
    /// events inside the actor, so a log recorded while the day logs were
    /// being fetched is never lost. Returns how many were filled; writes
    /// only when that is more than zero.
    @discardableResult
    public func applyMealBackfill(_ logs: [String: DailyFoodLog]) throws -> Int {
        loadIfNeeded()
        let result = UsageMealBackfill.apply(to: events, logs: logs)
        guard result.filled > 0 else { return 0 }
        events = result.events
        try persist()
        return result.filled
    }
}

/// Which usage events Reconciliation's verdicts let us link to Garmin's
/// `logId` (`UsageHistoryStore.linkGarminLogIds`): an entry confirmed 1:1,
/// or matched to a kept copy after a duplicate was cleaned up. A verdict
/// without a known `logId` links nothing -- that row is then deleted by the
/// id the dashboard shows, which is still the outbox id until it is read
/// back. Pure, so the mapping is tested without a drain.
public enum UsageLogLinks {
    public static func from(_ outcomes: [ReconciliationOutcome]) -> [String: String] {
        from(verdicts: outcomes.map { (entryId: $0.entryId, verdict: $0.verdict) })
    }

    public static func from(verdicts: [(entryId: UUID, verdict: ReconciliationOutcome.Verdict)]) -> [String: String] {
        var links: [String: String] = [:]
        for outcome in verdicts {
            let logId: String?
            switch outcome.verdict {
            case .confirmed(let confirmed): logId = confirmed
            case .duplicateResolved(let kept, _): logId = kept
            case .missingRequeued, .missingGaveUp, .reconciliationSkipped: logId = nil
            }
            guard let logId, !logId.isEmpty else { continue }
            links[outcome.entryId.uuidString] = logId
        }
        return links
    }
}

/// Pure ranking logic (task 13.2), extracted from the store so it is
/// testable with hand-built event arrays and no file I/O at all.
public enum QuickPick {
    public struct Entry: Sendable, Equatable {
        public let foodId: String
        public let servingId: String
        /// The quantity from the MOST RECENT event for this (food, serving)
        /// pair -- what a one-tap re-log should default to.
        public let numberOfUnits: Double
        public let score: Double
        public let lastUsedAt: Date
        public let useCount: Int
    }

    /// Ranks `(foodId, servingId)` pairs by a recency-weighted frequency
    /// score: each past event contributes `0.5 ^ (ageInDays / halfLifeDays)`
    /// to its pair's total, so logging the same thing often keeps it near
    /// the top, and logging something once a long time ago fades out --
    /// exactly the "combination of recency and frequency" the food-catalog
    /// spec calls for, as a single blended number rather than two signals
    /// the caller has to reconcile itself.
    ///
    /// Returns an empty array for empty input -- the spec's "no usage
    /// history exists yet -> quick-pick list is empty rather than populated
    /// with unranked guesses" scenario holds trivially.
    public static func rank(
        events: [UsageEvent],
        now: Date = Date(),
        halfLifeDays: Double = 7,
        limit: Int = 10
    ) -> [Entry] {
        guard !events.isEmpty else { return [] }

        struct Accumulator {
            var score: Double = 0
            var lastUsedAt: Date = .distantPast
            var lastNumberOfUnits: Double = 0
            var useCount: Int = 0
        }

        var byPair: [PairKey: Accumulator] = [:]
        for event in events {
            let key = PairKey(foodId: event.foodId, servingId: event.servingId)
            let ageInDays = max(0, now.timeIntervalSince(event.timestamp) / 86_400)
            let weight = pow(0.5, ageInDays / max(halfLifeDays, 0.0001))

            var accumulator = byPair[key] ?? Accumulator()
            accumulator.score += weight
            accumulator.useCount += 1
            if event.timestamp >= accumulator.lastUsedAt {
                accumulator.lastUsedAt = event.timestamp
                accumulator.lastNumberOfUnits = event.numberOfUnits
            }
            byPair[key] = accumulator
        }

        return byPair
            .map { key, accumulator in
                Entry(
                    foodId: key.foodId,
                    servingId: key.servingId,
                    numberOfUnits: accumulator.lastNumberOfUnits,
                    score: accumulator.score,
                    lastUsedAt: accumulator.lastUsedAt,
                    useCount: accumulator.useCount
                )
            }
            // Deterministic tie-break (equal score) by identifiers, so tests
            // and UI ordering never depend on `Dictionary`'s unordered
            // iteration.
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.foodId != $1.foodId { return $0.foodId < $1.foodId }
                return $0.servingId < $1.servingId
            }
            .prefix(limit)
            .map { $0 }
    }

    private struct PairKey: Hashable {
        let foodId: String
        let servingId: String
    }
}

/// Shared Application Support subdirectory for every JSON-file store in this
/// package (`UsageHistoryStore`, `ServingDefaultStore`, `CustomFoodStore`,
/// `FoodCacheStore`) -- one directory, one place to find them all by hand,
/// matching GarminKit's own "trivially inspectable" rationale for its
/// outbox file (there is no interactive debugger for this project -- see
/// openspec/config.yaml D9-style constraints referenced throughout GarminKit).
///
/// Public only so Gamification can reach `loadPersistedJSON` (see
/// PersistedStoreLoading.swift); `directory()` itself stays internal.
public enum FoodLogCoreStorage {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FoodLogCore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
