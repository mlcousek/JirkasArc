import FoodLogCore
import Foundation

// LifetimeStatsStore.swift
//
// achievements spec's "lifetime cumulative statistics persist independently
// of capped history stores" requirement (expand-gamification-depth
// design.md D4): several achievement ideas the owner asked for directly
// need a TRUE lifetime total -- total logs ever, total calories ever
// (the "eaten an elephant" style facts), the single highest-calorie day
// ever, first-ever-log date (anniversaries), and per-macro cumulative
// goal-hit-day counts. None of these can be safely recomputed from
// `UsageHistoryStore` (caps at 500 events, trims oldest) or
// `GoalStatusStore` (caps at 120 days) -- exactly the problem `XPStore`'s
// own header already documents and solves for total XP by keeping a small
// persisted running ledger instead of a derived value. This applies the
// same fix to the same class of problem.
//
// `UsageEvent` carries no calorie data (only foodId/servingId/numberOfUnits
// /timestamp/nutritionDay -- FoodLogCore/UsageHistory.swift's own header),
// so the calorie-dependent fields here can only advance from a value the
// APP layer already computed and passes in explicitly (see
// `GamificationEngine.handleLogConfirmed(now:calories:)`), not from
// anything this package can derive on its own.
public actor LifetimeStatsStore {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var totalLogsEver = 0
        public var totalCaloriesEver: Double = 0
        public var maxSingleDayCalories: Double = 0
        public var firstLogDate: Date?
        /// Keyed by `GoalMacro.rawValue`.
        public var goalHitDaysEver: [String: Int] = [:]
        /// Keyed by `GoalMacro.rawValue` -- the last day string counted for
        /// that macro, so re-recording the same day's status twice (a
        /// legitimate re-fetch, per `GoalStatusStore`'s own doc comment)
        /// never double-counts. Mirrors `XPStore`'s `lastStreakBonusDay`/
        /// `lastGoalBonusDay` idempotency pattern.
        public var lastCountedGoalDay: [String: String] = [:]
        /// Keyed by `GoalMacro.rawValue` -- EVERY day already counted for
        /// that macro (harden-gamification-data-integrity 2.3), so
        /// re-fetching an older day after a newer one never counts it
        /// again. `lastCountedGoalDay` alone only caught an immediate
        /// repeat. Unbounded on purpose: one short string per goal-hit day
        /// is about 4 KB a year per macro, and dropping old days would let
        /// a re-fetch of one of them count twice. Absent in a file written
        /// before it existed; `lastCountedGoalDay` seeds it then.
        public var countedGoalDays: [String: Set<String>]?
        /// Running calorie totals for the most recently touched handful of
        /// days (bounded by `maxTrackedDays`, evicted oldest-first) -- lets
        /// a day's total build up correctly across multiple logs, INCLUDING
        /// a backdated one revisiting a day after other days were logged
        /// in between, without needing to retain full daily history.
        var recentDayCalories: [String: Double] = [:]
        var recentDayOrder: [String] = []

        public init() {}
    }

    /// Generous relative to how far back a real backdated log is likely to
    /// go (the confirm screen's date picker, used occasionally to fix a
    /// missed entry) -- a backdate older than this still updates
    /// `totalCaloriesEver` correctly, just starts a fresh running total for
    /// `maxSingleDayCalories` purposes rather than adding to that day's
    /// already-evicted total. Accepted, bounded edge case.
    private static let maxTrackedDays = 14

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL = LifetimeStatsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("lifetime-stats.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile.
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: "LifetimeStatsStore")
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "LifetimeStatsStore")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func current() -> Snapshot {
        loadIfNeeded()
        return snapshot
    }

    public func goalHitDays(_ macro: GoalMacro) -> Int {
        loadIfNeeded()
        return snapshot.goalHitDaysEver[macro.rawValue] ?? 0
    }

    /// Called once per confirmed log (`GamificationEngine.handleLogConfirmed`).
    /// `calories` is whatever the confirm screen already computed for that
    /// entry -- `nil` for anything without a known calorie value, in which
    /// case the calorie-dependent fields simply don't advance for that log.
    /// `entries` is how many durable food entries the log made (a meal
    /// preset makes one per ingredient, harden-gamification-data-integrity
    /// 2.2); `calories` is their total.
    public func recordLog(nutritionDay: String, calories: Double?, now: Date, entries: Int = 1) throws {
        loadIfNeeded()
        snapshot.totalLogsEver += max(1, entries)
        if let existing = snapshot.firstLogDate {
            snapshot.firstLogDate = min(existing, now)
        } else {
            snapshot.firstLogDate = now
        }
        if let calories, calories > 0 {
            snapshot.totalCaloriesEver += calories
            if let existing = snapshot.recentDayCalories[nutritionDay] {
                snapshot.recentDayCalories[nutritionDay] = existing + calories
            } else {
                snapshot.recentDayCalories[nutritionDay] = calories
                snapshot.recentDayOrder.append(nutritionDay)
                if snapshot.recentDayOrder.count > Self.maxTrackedDays {
                    let overflow = snapshot.recentDayOrder.count - Self.maxTrackedDays
                    for day in snapshot.recentDayOrder.prefix(overflow) { snapshot.recentDayCalories.removeValue(forKey: day) }
                    snapshot.recentDayOrder.removeFirst(overflow)
                }
            }
            snapshot.maxSingleDayCalories = max(snapshot.maxSingleDayCalories, snapshot.recentDayCalories[nutritionDay] ?? 0)
        }
        try persist()
    }

    /// Called alongside `GoalStatusStore.record(_:)` from
    /// `GamificationEngine.refreshGoalStatus(for:)`.
    public func recordGoalStatus(_ status: DailyGoalStatus) throws {
        loadIfNeeded()
        countGoalDays(status)
        try persist()
    }

    /// Counts each met macro of `status`'s day at most once, ever.
    private func countGoalDays(_ status: DailyGoalStatus) {
        // A ledger written before every counted day was kept knows only the
        // last one per macro, which is what it guarded.
        var counted = snapshot.countedGoalDays ?? snapshot.lastCountedGoalDay.mapValues { Set([$0]) }
        for macro in GoalMacro.allCases where status.met(macro) {
            guard !counted[macro.rawValue, default: []].contains(status.date) else { continue }
            counted[macro.rawValue, default: []].insert(status.date)
            snapshot.goalHitDaysEver[macro.rawValue, default: 0] += 1
            snapshot.lastCountedGoalDay[macro.rawValue] = status.date
        }
        snapshot.countedGoalDays = counted
    }

    /// design.md's accepted Risk: a device that already has real usage
    /// history when this ledger first ships starts every counter at zero
    /// unless backfilled. Runs once (guarded by the ledger genuinely being
    /// empty, not merely small) and can only recover what the CAPPED
    /// `events`/`goalStatuses` still happen to retain -- calorie data and
    /// any foodIds already rolled off `UsageHistoryStore`'s cap are gone
    /// for good, which is the accepted, bounded gap design.md documents.
    public func backfillIfEmpty(events: [UsageEvent], goalStatuses: [DailyGoalStatus]) throws {
        loadIfNeeded()
        guard snapshot.totalLogsEver == 0, snapshot.firstLogDate == nil else { return }
        guard !events.isEmpty || !goalStatuses.isEmpty else { return }

        snapshot.totalLogsEver = events.count
        if let earliest = events.map(\.timestamp).min() {
            snapshot.firstLogDate = earliest
        }
        for status in goalStatuses {
            countGoalDays(status)
        }
        try persist()
    }
}
