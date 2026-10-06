// FoodLogDeletionQueue.swift
//
// improve-food-day-flow (E2, design D1): deleting a food entry that is
// already in Garmin, as a durable queue instead of a direct call. Before
// this, delete was the one change to the food log that needed the network
// at the moment of the tap: offline it failed with an alert and the entry
// stayed. Every other change (add, edit, move, duplicate) was already saved
// on the phone first and delivered later.
//
// Why a SEPARATE file and record, and not an "operation" on `OutboxEntry`:
// an `OutboxEntry` is a food to create (meal, food id, serving, amount) and
// its file is read by Reconciliation, the dashboard, the mode switch and
// the sync queue -- and by whatever build is on the phone. A delete has none
// of those fields, and an older build would read it as a create. So a delete
// is its own small record (`FoodLogDeletion`) in its own per-process file,
// `food-delete-outbox-<process>.json`, next to the outbox file. The food
// `Outbox` actor owns both stores, so one actor stamps the account, signs
// entries over on sign-out and answers the sync queue.
//
// The drain (`Outbox.drainDeletions`) follows `Outbox.drain` rule for rule:
//   - 2xx, and 404 (the entry is already gone): delivered;
//   - 429: an attempt is counted, `Retry-After` is honoured and the whole
//     cycle stops;
//   - an auth failure, or no connection (`ConnectivityFailure`): the cycle
//     stops and NO attempt is counted;
//   - any other 4xx except 408: gives up at once (retrying cannot fix it);
//   - anything else: capped backoff with jitter, and it gives up once
//     `maxAttempts` are spent.
// A delete stamped with another Garmin account is held, never sent
// (`AccountScope`, DeliverySafety.swift). There is NO send marker
// (`sendStartedAt`): repeating a delete is harmless -- the second answers
// 404, which is success.
//
// A delivered delete is KEPT as `.sent` until the day has been read again
// without that entry (`pruneConfirmedDeletions`), or for
// `confirmedRetention` at most. Without it the row would come back between
// Garmin's answer and the app's next read of that day.
//
// "Garmin said yes" is NOT trusted on its own (review finding, 2026-10-06).
// The delete route has never been exercised on a device by this project, and
// a 404 counts as "already gone" -- so a wrong route, date or id would make
// every delete look delivered while the entry still sits in Garmin, hidden
// on the phone. So the same re-read that drops a confirmed delete also
// CHECKS it: when the day still lists the entry and Garmin's answer is older
// than `deletionConfirmationGrace` (a read right after a delete may simply
// be stale), the delete goes back to `.failed` with an error that says so.
// The row then reappears as "Couldn't delete", counts again, and offers
// "Retry" and "Keep entry" -- loud, never a silently hidden entry.
//
// The route is the one the app already called for this
// (`DELETE /nutrition-service/food/logs/{date}`, body `{ "logIds": [...] }`,
// docs/garmin-routes.json: last verified 2026-09-16, modelled on a
// live-tested client and not yet exercised by this project). Nothing here
// invents a route or a body.
//
// Depended on by: Outbox.swift (owns the store), FoodLogCore's
// LogEntryCoordinator (queues), MealDashboard (overlays), OutboxBacklog and
// BackgroundOutboxDelivery, and the app's DayLogLoader, AppEnvironment and
// SyncQueueView. Tests: FoodLogDeletionQueueTests, StoreFixtureTests.

import Foundation

/// Where a queued delete stands. Its own type (not `OutboxEntryState`): a
/// delete never has a "created, awaiting delete" step.
public enum FoodLogDeletionState: String, Codable, Sendable, Equatable {
    /// Waiting to be sent (or backing off after a failed attempt).
    case pending
    /// Garmin confirmed it (or the entry was already gone). Kept until the
    /// day is read again without that entry.
    case sent
    /// Gave up; waits for "Retry" or "Keep entry".
    case failed
}

/// One queued delete of a food entry that is in Garmin.
public struct FoodLogDeletion: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// `yyyy-MM-dd`: the delete route's path component.
    public let date: String
    /// The hex `logId` of the entry as Garmin read it back.
    public let logId: String
    public var state: FoodLogDeletionState
    public var attemptCount: Int
    public var lastError: String?
    public let createdAt: Date
    /// Not attempted again before this time (backoff, `Retry-After`).
    public var nextAttemptAt: Date
    /// When Garmin confirmed it; `nil` until then.
    public var deliveredAt: Date?
    /// The Garmin account it was made under (`GarminAccountKey`, hashed);
    /// `nil` = not known. Only ever delivered to that account.
    public var accountKey: String?

    public init(
        id: UUID = UUID(),
        date: String,
        logId: String,
        state: FoodLogDeletionState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        nextAttemptAt: Date = Date(),
        deliveredAt: Date? = nil,
        accountKey: String? = nil
    ) {
        self.id = id
        self.date = date
        self.logId = logId
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
        self.deliveredAt = deliveredAt
        self.accountKey = accountKey
    }

    /// Still to be sent.
    public var isWaiting: Bool { state == .pending }
    /// Garmin has confirmed it.
    public var isConfirmed: Bool { state == .sent }
    /// Gave up: the sync queue and the row offer "Retry" and "Keep entry".
    public var needsManualRetry: Bool { state == .failed }

    func isDue(now: Date) -> Bool {
        state == .pending && nextAttemptAt <= now
    }
}

/// Thrown by `Outbox.queueDeletion` for an entry without a Garmin id or a
/// day: there is nothing the delete route could be asked for.
public enum FoodLogDeletionError: Error, Sendable, Equatable {
    case missingIdentifier
}

public struct FoodLogDeletionDrainResult: Sendable, Equatable {
    /// Deletes Garmin confirmed in this cycle (a 404 included).
    public let delivered: [FoodLogDeletion]
    /// Deletes that gave up in this cycle and now need the user.
    public let failed: [FoodLogDeletion]
    public let stoppedDueToRateLimit: Bool
    public let authOutcome: DrainAuthOutcome

    public init(
        delivered: [FoodLogDeletion] = [],
        failed: [FoodLogDeletion] = [],
        stoppedDueToRateLimit: Bool = false,
        authOutcome: DrainAuthOutcome = .none
    ) {
        self.delivered = delivered
        self.failed = failed
        self.stoppedDueToRateLimit = stoppedDueToRateLimit
        self.authOutcome = authOutcome
    }
}

// MARK: - Persistence

/// JSON-file-backed store, one file per process -- the delete queue's twin
/// of `OutboxStore` (same directory, same encoder, same "never write over a
/// file this process could not read" rule).
actor FoodLogDeletionStore {
    private let fileURL: URL
    private var deletions: [FoodLogDeletion] = []
    private var loaded = false
    /// Deletes a drain is sending right now; "Keep entry" is refused for
    /// these (an entry cannot be un-deleted).
    private var claimedIds: Set<UUID> = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(processName: String = "default") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GarminKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("food-delete-outbox-\(processName).json")
    }

    /// A throwaway file for an `Outbox` built from a bare `OutboxStore`
    /// (the tests' initializer) that names no delete store of its own.
    static func temporary() -> FoodLogDeletionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("garminkit-food-deletions-" + UUID().uuidString)
            .appendingPathExtension("json")
        return FoodLogDeletionStore(fileURL: url)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load([FoodLogDeletion].self, from: fileURL, decoder: JSONDecoder(), category: "FoodLogDeletionStore")
        deletions = result.value ?? []
        // Unreadable (e.g. before first unlock): retry on the next access.
        loaded = !result.isUnreadable
    }

    /// Every save funnels through here. The in-memory copy changes only
    /// once the write has succeeded.
    private func write(_ list: [FoodLogDeletion]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "FoodLogDeletionStore")
        let data = try JSONEncoder().encode(list)
        try data.write(to: fileURL, options: .atomic)
        // Like `OutboxStore`: readable by a background drain before the
        // first unlock of a session, encrypted at rest once the phone is off.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        deletions = list
    }

    func all() -> [FoodLogDeletion] {
        loadIfNeeded()
        return deletions
    }

    func due(now: Date) -> [FoodLogDeletion] {
        loadIfNeeded()
        return deletions.filter { $0.isDue(now: now) }
    }

    /// Adds `deletion`, or answers with the record already queued for the
    /// same entry: a waiting or confirmed one is returned as it is, one that
    /// gave up is made to wait again (deleting the entry a second time IS a
    /// retry). One record per entry, whatever the taps.
    func enqueue(_ deletion: FoodLogDeletion, now: Date) throws -> FoodLogDeletion {
        loadIfNeeded()
        var updated = deletions
        if let index = updated.firstIndex(where: { $0.date == deletion.date && $0.logId == deletion.logId }) {
            guard updated[index].state == .failed else { return updated[index] }
            updated[index].state = .pending
            updated[index].attemptCount = 0
            updated[index].lastError = nil
            updated[index].nextAttemptAt = now
            try write(updated)
            return updated[index]
        }
        updated.append(deletion)
        try write(updated)
        return deletion
    }

    func update(_ deletion: FoodLogDeletion) throws {
        loadIfNeeded()
        guard let index = deletions.firstIndex(where: { $0.id == deletion.id }) else { return }
        var updated = deletions
        updated[index] = deletion
        try write(updated)
    }

    /// Marks `id` in flight and returns its CURRENT value, or `nil` when it
    /// is gone, already claimed or no longer due.
    func claim(id: UUID, now: Date) -> FoodLogDeletion? {
        loadIfNeeded()
        guard !claimedIds.contains(id),
              let deletion = deletions.first(where: { $0.id == id }),
              deletion.isDue(now: now)
        else { return nil }
        claimedIds.insert(id)
        return deletion
    }

    func release(id: UUID) {
        claimedIds.remove(id)
    }

    /// "Retry": a delete that gave up waits again, from attempt 0. A
    /// waiting one is only made due now; a confirmed one is left alone.
    func retry(id: UUID, now: Date) throws {
        loadIfNeeded()
        guard let index = deletions.firstIndex(where: { $0.id == id }), deletions[index].state != .sent else { return }
        var updated = deletions
        updated[index].state = .pending
        updated[index].attemptCount = 0
        updated[index].lastError = nil
        updated[index].nextAttemptAt = now
        try write(updated)
    }

    /// "Keep entry": removes a delete Garmin has not confirmed. Refused
    /// while a drain is sending it, and once it is confirmed; nothing
    /// changes when it throws.
    func cancel(id: UUID) throws {
        loadIfNeeded()
        guard !claimedIds.contains(id) else { throw OutboxEditError.entryInFlight }
        guard let index = deletions.firstIndex(where: { $0.id == id }) else { throw OutboxEditError.entryNotFound }
        guard deletions[index].state != .sent else { throw OutboxEditError.alreadyDelivered }
        var updated = deletions
        updated.remove(at: index)
        try write(updated)
    }

    /// Ties every unconfirmed, unstamped delete to `key` (signing out).
    func assignUnscoped(to key: String) throws {
        loadIfNeeded()
        var updated = deletions
        var changed = false
        for index in updated.indices where updated[index].accountKey == nil && updated[index].state != .sent {
            updated[index].accountKey = key
            changed = true
        }
        guard changed else { return }
        try write(updated)
    }

    /// `date` was read again and lists `remainingLogIds`. For each confirmed
    /// delete of that day:
    ///   - its entry is no longer listed: the record is done and dropped;
    ///   - its entry is STILL listed and Garmin's answer is older than
    ///     `grace`: the delete did not happen -- the record becomes
    ///     `.failed` with `stillListedError`, so the row comes back;
    ///   - still listed inside `grace`: left alone (the read may be stale).
    /// Returns the records that went back to `.failed`.
    func checkConfirmed(date: String, remainingLogIds: Set<String>, now: Date, grace: TimeInterval) throws -> [FoodLogDeletion] {
        loadIfNeeded()
        var updated: [FoodLogDeletion] = []
        var notApplied: [FoodLogDeletion] = []
        var changed = false
        for deletion in deletions {
            guard deletion.state == .sent, deletion.date == date else {
                updated.append(deletion)
                continue
            }
            guard remainingLogIds.contains(deletion.logId) else {
                changed = true
                continue
            }
            let confirmedAt = deletion.deliveredAt ?? deletion.createdAt
            guard now.timeIntervalSince(confirmedAt) > grace else {
                updated.append(deletion)
                continue
            }
            var failed = deletion
            failed.state = .failed
            failed.lastError = FoodLogDeletionStore.stillListedError
            failed.deliveredAt = nil
            updated.append(failed)
            notApplied.append(failed)
            changed = true
        }
        guard changed else { return [] }
        try write(updated)
        return notApplied
    }

    /// What a delete is marked with when Garmin answered it as done but a
    /// later read of the day still lists the entry.
    static let stillListedError = "Garmin answered the delete as done, but the day still lists the entry"

    /// Drops the confirmed deletes Garmin confirmed before `cutoff`.
    func removeConfirmed(before cutoff: Date) throws {
        loadIfNeeded()
        let kept = deletions.filter { deletion in
            !(deletion.state == .sent && (deletion.deliveredAt ?? deletion.createdAt) < cutoff)
        }
        guard kept.count != deletions.count else { return }
        try write(kept)
    }
}

// MARK: - The queue, on the food outbox

extension Outbox {
    /// How long a confirmed delete is kept when its day is never read
    /// again (after that, a copy of the day still listing the entry would
    /// be a week old).
    public static let confirmedDeletionRetention: TimeInterval = 7 * 24 * 3600

    /// How long after Garmin's answer a read of the day may still list the
    /// entry without that meaning anything (the read may have started
    /// before the delete landed, or be a moment behind). After it, an entry
    /// that is still listed was not deleted.
    public static let deletionConfirmationGrace: TimeInterval = 5 * 60

    /// Queues deleting the Garmin entry `logId` of `date`. Durable on
    /// return and makes no network call, like `logFood`. Queuing the same
    /// entry again returns the record already there (one that gave up waits
    /// again).
    @discardableResult
    public func queueDeletion(logId: String, date: String, now: Date = Date()) async throws -> FoodLogDeletion {
        guard !logId.isEmpty, !date.isEmpty else { throw FoodLogDeletionError.missingIdentifier }
        // Stamped with the account signed in now (DeliverySafety.swift).
        let currentAccount = await accountKey()
        let deletion = FoodLogDeletion(
            date: date,
            logId: logId,
            createdAt: now,
            nextAttemptAt: now,
            accountKey: currentAccount
        )
        return try await deletions.enqueue(deletion, now: now)
    }

    /// Every queued delete: waiting, confirmed and given up.
    public func allDeletions() async -> [FoodLogDeletion] {
        await deletions.all()
    }

    /// The user's "Retry" of a delete that gave up.
    public func retryDeletion(id: UUID, now: Date = Date()) async throws {
        try await deletions.retry(id: id, now: now)
    }

    /// The user's "Keep entry": the delete leaves the queue and the entry
    /// stays in Garmin. Throws `OutboxEditError.entryInFlight` while a drain
    /// is sending it, `.alreadyDelivered` once Garmin confirmed it and
    /// `.entryNotFound` for an unknown id.
    public func cancelDeletion(id: UUID) async throws {
        try await deletions.cancel(id: id)
    }

    /// Called after `date` was read from Garmin (`remainingLogIds` = every
    /// entry that read lists). A confirmed delete whose entry is no longer
    /// listed is done and leaves the file. One whose entry is STILL listed
    /// more than `deletionConfirmationGrace` after Garmin's answer was not
    /// applied: it goes back to `.failed` ("Couldn't delete", Retry, "Keep
    /// entry") instead of hiding an entry that is still in Garmin -- see
    /// this file's header. Returns the deletes that went back to `.failed`.
    @discardableResult
    public func pruneConfirmedDeletions(date: String, remainingLogIds: Set<String>, now: Date = Date()) async -> [FoodLogDeletion] {
        do {
            let notApplied = try await deletions.checkConfirmed(
                date: date,
                remainingLogIds: remainingLogIds,
                now: now,
                grace: Self.deletionConfirmationGrace
            )
            if !notApplied.isEmpty {
                DiagnosticsLog.log(.error, category: "Outbox", "delete: Garmin answered \(notApplied.count) delete(s) on \(date) as done, but the day still lists the entr(ies); marked as not deleted")
            }
            return notApplied
        } catch {
            DiagnosticsLog.log(.warning, category: "Outbox", "couldn't check confirmed deletes of \(date): \(error)")
            return []
        }
    }

    /// Sends every due delete once. See this file's header for the rules;
    /// they are `drain`'s, applied to a delete.
    @discardableResult
    public func drainDeletions(
        using deliverer: some FoodLogDelivering,
        now: Date = Date(),
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) async -> FoodLogDeletionDrainResult {
        // A drain already in flight wins; an overlapping caller gets a
        // harmless empty result (the same guard as `drain`).
        guard !isDrainingDeletions else { return FoodLogDeletionDrainResult() }
        isDrainingDeletions = true
        defer { isDrainingDeletions = false }

        var delivered: [FoodLogDeletion] = []
        var failed: [FoodLogDeletion] = []
        var stoppedDueToRateLimit = false
        var authOutcome: DrainAuthOutcome = .none

        // Confirmed deletes whose day was never read again.
        try? await deletions.removeConfirmed(before: now.addingTimeInterval(-Self.confirmedDeletionRetention))

        let currentAccount = await accountKey()
        for snapshot in await deletions.due(now: now) {
            // Another account's delete is held, not sent.
            guard AccountScope.mayDeliver(entryKey: snapshot.accountKey, currentKey: currentAccount) else { continue }
            guard var deletion = await deletions.claim(id: snapshot.id, now: now) else { continue }

            var stop = false
            do {
                do {
                    try await deliverer.deleteFoodLogEntries(logIds: [deletion.logId], date: deletion.date)
                } catch GarminClientError.httpError(let statusCode, _) where statusCode == 404 {
                    // Already gone (deleted in Garmin Connect, or an earlier
                    // attempt landed and its answer was lost): the goal is met.
                    DiagnosticsLog.log(.info, category: "Outbox", "delete: the entry on \(deletion.date) was already gone (404); treating as deleted")
                }
                deletion.state = .sent
                deletion.lastError = nil
                deletion.deliveredAt = now
                delivered.append(deletion)
            } catch GarminClientError.rateLimited(let retryAfterSeconds) {
                deletion.attemptCount += 1
                deletion.lastError = "rate limited (429)"
                deletion.nextAttemptAt = now.addingTimeInterval(
                    retryAfterSeconds ?? RetryBackoff.delay(attempt: deletion.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                )
                stoppedDueToRateLimit = true
                stop = true
            } catch GarminAuthError.longLivedTokenExpired {
                deletion.lastError = "auth: long-lived token expired"
                authOutcome = .longLivedTokenExpired
                stop = true
            } catch GarminAuthError.notSignedIn {
                deletion.lastError = "auth: not signed in"
                authOutcome = .notSignedIn
                stop = true
            } catch let error as URLError where ConnectivityFailure.matches(error) {
                // Offline is not a delivery failure: no attempt, no backoff.
                deletion.lastError = "offline: " + String(error.localizedDescription.prefix(200))
                stop = true
            } catch {
                deletion.attemptCount += 1
                deletion.lastError = String(String(describing: error).prefix(300))
                if Self.isPermanentDeleteRejection(error) || deletion.attemptCount >= maxAttempts {
                    deletion.state = .failed
                    failed.append(deletion)
                    DiagnosticsLog.log(.error, category: "Outbox", "delete: the entry on \(deletion.date) couldn't be removed after \(deletion.attemptCount) attempt(s); waiting for a manual retry")
                } else {
                    deletion.nextAttemptAt = now.addingTimeInterval(
                        RetryBackoff.delay(attempt: deletion.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                    )
                }
            }

            // A confirmed delete whose state can't be saved is simply sent
            // again by a later drain and answers 404.
            do {
                try await deletions.update(deletion)
            } catch {
                DiagnosticsLog.log(.warning, category: "Outbox", "delete: couldn't save an attempt's result (\(error))")
            }
            await deletions.release(id: deletion.id)
            if stop { break }
        }

        if !delivered.isEmpty || !failed.isEmpty || authOutcome != .none {
            DiagnosticsLog.log(
                delivered.isEmpty && !failed.isEmpty ? .warning : .info,
                category: "Outbox",
                "delete drain: \(delivered.count) confirmed, \(failed.count) gave up, rateLimited=\(stoppedDueToRateLimit), authOutcome=\(authOutcome)"
            )
        }
        return FoodLogDeletionDrainResult(
            delivered: delivered,
            failed: failed,
            stoppedDueToRateLimit: stoppedDueToRateLimit,
            authOutcome: authOutcome
        )
    }
}
